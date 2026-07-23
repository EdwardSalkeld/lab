package mirror

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

const (
	defaultSourceServer      = "https://vault.bitwarden.eu"
	defaultDestinationServer = "https://vault.alcachofa.faith"
	defaultWorkDir           = "/run/bitwarden-mirror"
	defaultStateDir          = "/var/lib/bitwarden-mirror"
	defaultRetryAttempts     = 3
)

type Config struct {
	SourceServer      string
	DestinationServer string
	WorkDir           string
	StateDir          string
	DryRun            bool
	DeleteConcurrency int
}

func (c Config) withDefaults() Config {
	if c.SourceServer == "" {
		c.SourceServer = defaultSourceServer
	}
	if c.DestinationServer == "" {
		c.DestinationServer = defaultDestinationServer
	}
	if c.WorkDir == "" {
		c.WorkDir = defaultWorkDir
	}
	if c.StateDir == "" {
		c.StateDir = defaultStateDir
	}
	if c.DeleteConcurrency <= 0 {
		c.DeleteConcurrency = 8
	}
	return c
}

type Credentials struct {
	ClientID       string
	ClientSecret   string
	MasterPassword string
}

type Environment struct {
	Source      Credentials
	Destination Credentials
}

func EnvironmentFromEnv() (Environment, error) {
	env := Environment{
		Source: Credentials{
			ClientID:       os.Getenv("SOURCE_BW_CLIENTID"),
			ClientSecret:   os.Getenv("SOURCE_BW_CLIENTSECRET"),
			MasterPassword: os.Getenv("SOURCE_BW_MASTER_PASSWORD"),
		},
		Destination: Credentials{
			ClientID:       os.Getenv("DEST_BW_CLIENTID"),
			ClientSecret:   os.Getenv("DEST_BW_CLIENTSECRET"),
			MasterPassword: os.Getenv("DEST_BW_MASTER_PASSWORD"),
		},
	}

	var missing []string
	require := func(name, value string) {
		if value == "" {
			missing = append(missing, name)
		}
	}
	require("SOURCE_BW_CLIENTID", env.Source.ClientID)
	require("SOURCE_BW_CLIENTSECRET", env.Source.ClientSecret)
	require("SOURCE_BW_MASTER_PASSWORD", env.Source.MasterPassword)
	require("DEST_BW_CLIENTID", env.Destination.ClientID)
	require("DEST_BW_CLIENTSECRET", env.Destination.ClientSecret)
	require("DEST_BW_MASTER_PASSWORD", env.Destination.MasterPassword)
	if len(missing) > 0 {
		return Environment{}, fmt.Errorf("missing required environment variables: %v", missing)
	}

	return env, nil
}

type Runner interface {
	Run(ctx context.Context, cmd Command) ([]byte, error)
}

type Command struct {
	Args []string
	Env  map[string]string
}

type FileOps struct {
	MkdirAll  func(path string, perm os.FileMode) error
	Remove    func(path string) error
	RemoveAll func(path string) error
}

func DefaultFileOps() FileOps {
	return FileOps{
		MkdirAll:  os.MkdirAll,
		Remove:    os.Remove,
		RemoveAll: os.RemoveAll,
	}
}

type Mirror struct {
	Config Config
	Env    Environment
	Runner Runner
	Files  FileOps
	Logger *log.Logger
	Sleep  func(context.Context, time.Duration) error
}

func (m Mirror) Run(ctx context.Context) error {
	if m.Runner == nil {
		return errors.New("runner is required")
	}

	cfg := m.Config.withDefaults()
	files := m.Files
	if files.MkdirAll == nil {
		files.MkdirAll = os.MkdirAll
	}
	if files.Remove == nil {
		files.Remove = os.Remove
	}
	if files.RemoveAll == nil {
		files.RemoveAll = os.RemoveAll
	}
	logger := m.Logger
	if logger == nil {
		logger = log.New(io.Discard, "", 0)
	}
	sleep := m.Sleep
	if sleep == nil {
		sleep = sleepWithContext
	}

	if err := files.MkdirAll(cfg.WorkDir, 0o700); err != nil {
		return fmt.Errorf("create work dir %s: %w", cfg.WorkDir, err)
	}
	for _, dir := range []string{cfg.sourceAppdataDir(), cfg.destinationAppdataDir()} {
		if err := files.MkdirAll(dir, 0o700); err != nil {
			return fmt.Errorf("create appdata dir %s: %w", dir, err)
		}
	}

	exportPath := filepath.Join(cfg.WorkDir, "bitwarden-export.json")
	cleanup := func() error {
		if err := files.Remove(exportPath); err != nil && !errors.Is(err, os.ErrNotExist) {
			return fmt.Errorf("remove plaintext export %s: %w", exportPath, err)
		}
		return nil
	}
	defer func() {
		if err := cleanup(); err != nil {
			logger.Printf("cleanup failed: %v", err)
		}
	}()

	if _, err := m.loginUnlockSyncExport(ctx, "source", cfg.SourceServer, cfg.sourceAppdataDir(), m.Env.Source, exportPath, files, logger, sleep); err != nil {
		return err
	}

	destSession, err := m.loginUnlockWithRecovery(ctx, "destination", cfg.DestinationServer, cfg.destinationAppdataDir(), m.Env.Destination, files, logger, sleep)
	if err != nil {
		return err
	}

	destEnv := bwEnv(cfg.destinationAppdataDir(), m.Env.Destination, destSession)
	items, err := m.listObjects(ctx, "items", destEnv, false)
	if err != nil {
		return err
	}
	folders, err := m.listObjects(ctx, "folders", destEnv, true)
	if err != nil {
		return err
	}

	if cfg.DryRun {
		logger.Printf("dry run: would permanently delete %d destination items and %d folders", len(items), len(folders))
		logger.Printf("dry run: would import %s into destination", exportPath)
		return nil
	}

	logger.Printf("permanently deleting %d destination items", len(items))
	if err := m.deleteObjects(ctx, "item", items, cfg, m.Env.Destination, files, logger, sleep, cfg.DeleteConcurrency, 25); err != nil {
		return err
	}
	logger.Printf("permanently deleting %d destination folders", len(folders))
	if err := m.deleteObjects(ctx, "folder", folders, cfg, m.Env.Destination, files, logger, sleep, cfg.DeleteConcurrency, 10); err != nil {
		return err
	}

	logger.Printf("importing %s into destination", exportPath)
	if err := m.run(ctx, "import destination vault", Command{
		Args: []string{"import", "bitwardenjson", exportPath},
		Env:  destEnv,
	}); err != nil {
		return err
	}
	logger.Printf("import complete")

	if err := cleanup(); err != nil {
		return err
	}
	return nil
}

func (m Mirror) deleteObjects(ctx context.Context, kind string, objects []bwObject, cfg Config, creds Credentials, files FileOps, logger *log.Logger, sleep func(context.Context, time.Duration) error, concurrency int, logEvery int64) error {
	if len(objects) == 0 {
		return nil
	}
	if concurrency < 1 {
		concurrency = 1
	}
	if concurrency > len(objects) {
		concurrency = len(objects)
	}
	if logEvery < 1 {
		logEvery = 1
	}

	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	jobs := make(chan bwObject)
	errs := make(chan error, 1)
	var done int64
	var wg sync.WaitGroup

	envs := make([]map[string]string, 0, concurrency)
	for workerID := range concurrency {
		appdataDir := cfg.destinationDeleteAppdataDir(workerID)
		env, err := m.destinationDeleteEnv(ctx, cfg.DestinationServer, appdataDir, creds, files, logger, sleep)
		if err != nil {
			return err
		}
		envs = append(envs, env)
	}

	for _, env := range envs {
		wg.Add(1)
		go func(env map[string]string) {
			defer wg.Done()

			for object := range jobs {
				if err := m.run(ctx, "delete destination "+kind, Command{
					Args: []string{"delete", kind, object.ID, "--permanent"},
					Env:  env,
				}); err != nil {
					select {
					case errs <- err:
						cancel()
					default:
					}
					return
				}

				current := atomic.AddInt64(&done, 1)
				if current == 1 || current%logEvery == 0 || current == int64(len(objects)) {
					logger.Printf("deleted destination %ss %d/%d", kind, current, len(objects))
				}
			}
		}(env)
	}

send:
	for _, object := range objects {
		select {
		case <-ctx.Done():
			break send
		case jobs <- object:
		}
	}
	close(jobs)
	wg.Wait()

	select {
	case err := <-errs:
		return err
	default:
		return nil
	}
}

func (m Mirror) destinationDeleteEnv(ctx context.Context, server, appdataDir string, creds Credentials, files FileOps, logger *log.Logger, sleep func(context.Context, time.Duration) error) (map[string]string, error) {
	if err := files.MkdirAll(appdataDir, 0o700); err != nil {
		return nil, fmt.Errorf("create destination delete appdata dir %s: %w", appdataDir, err)
	}
	session, err := m.loginUnlockWithRecovery(ctx, "destination delete worker", server, appdataDir, creds, files, logger, sleep)
	if err != nil {
		return nil, err
	}
	return bwEnv(appdataDir, creds, session), nil
}

func (m Mirror) loginUnlockSyncExport(ctx context.Context, label, server, appdataDir string, creds Credentials, exportPath string, files FileOps, logger *log.Logger, sleep func(context.Context, time.Duration) error) (string, error) {
	session, err := m.loginUnlockWithRecovery(ctx, label, server, appdataDir, creds, files, logger, sleep)
	if err != nil {
		return "", err
	}
	env := bwEnv(appdataDir, creds, session)
	if err := m.run(ctx, label+" sync", Command{Args: []string{"sync"}, Env: env}); err != nil {
		return "", err
	}
	if err := m.run(ctx, label+" export", Command{
		Args: []string{"export", "--format", "json", "--output", exportPath},
		Env:  env,
	}); err != nil {
		return "", err
	}
	return session, nil
}

func (m Mirror) loginUnlockWithRecovery(ctx context.Context, label, server, appdataDir string, creds Credentials, files FileOps, logger *log.Logger, sleep func(context.Context, time.Duration) error) (string, error) {
	var lastErr error
	for attempt := 1; attempt <= defaultRetryAttempts; attempt++ {
		session, err := m.loginUnlock(ctx, label, server, appdataDir, creds)
		if err == nil {
			return session, nil
		}
		lastErr = err

		recovery := classifyLoginError(err)
		if !recovery.retry || attempt == defaultRetryAttempts {
			return "", err
		}

		if recovery.resetAppdata {
			if err := files.RemoveAll(appdataDir); err != nil && !errors.Is(err, os.ErrNotExist) {
				return "", fmt.Errorf("%s reset appdata %s: %w", label, appdataDir, err)
			}
			if err := files.MkdirAll(appdataDir, 0o700); err != nil {
				return "", fmt.Errorf("%s recreate appdata %s: %w", label, appdataDir, err)
			}
			logger.Printf("%s: cleared appdata %s after recoverable bw state error", label, appdataDir)
		}

		backoff := retryBackoff(attempt)
		logger.Printf("%s: retrying after %s due to recoverable error: %v", label, backoff, err)
		if err := sleep(ctx, backoff); err != nil {
			return "", err
		}
	}
	return "", lastErr
}

func (m Mirror) loginUnlock(ctx context.Context, label, server, appdataDir string, creds Credentials) (string, error) {
	env := bwEnv(appdataDir, creds, "")

	status, err := m.status(ctx, label, env)
	if err != nil || status.Status == "" || status.Status == "unauthenticated" {
		if err := m.run(ctx, label+" configure server", Command{
			Args: []string{"config", "server", server},
			Env:  env,
		}); err != nil {
			return "", err
		}
		if err := m.run(ctx, label+" login", Command{
			Args: []string{"login", "--apikey"},
			Env:  env,
		}); err != nil {
			return "", err
		}
	} else if status.ServerURL != "" && status.ServerURL != server {
		return "", fmt.Errorf("%s appdata is logged into %s, expected %s; remove %s or logout manually", label, status.ServerURL, server, appdataDir)
	}

	out, err := m.Runner.Run(ctx, Command{
		Args: []string{"unlock", "--raw", "--passwordenv", "BW_PASSWORD"},
		Env:  env,
	})
	if err != nil {
		return "", fmt.Errorf("%s unlock: bw %v: %w", label, []string{"unlock", "--raw", "--passwordenv", "BW_PASSWORD"}, err)
	}
	session := string(bytesTrimSpace(out))
	if session == "" {
		return "", fmt.Errorf("%s unlock: bw returned empty session", label)
	}
	return session, nil
}

type loginRecovery struct {
	retry        bool
	resetAppdata bool
}

func classifyLoginError(err error) loginRecovery {
	message := err.Error()
	switch {
	case strings.Contains(message, "bw returned empty session"):
		return loginRecovery{retry: true, resetAppdata: true}
	case strings.Contains(message, "Rate limit exceeded. Try again later."):
		return loginRecovery{retry: true}
	case strings.Contains(message, "Too many requests, try again later."):
		return loginRecovery{retry: true}
	default:
		return loginRecovery{}
	}
}

type bwStatus struct {
	Status    string `json:"status"`
	ServerURL string `json:"serverUrl"`
}

func (m Mirror) status(ctx context.Context, label string, env map[string]string) (bwStatus, error) {
	out, err := m.Runner.Run(ctx, Command{
		Args: []string{"status", "--raw"},
		Env:  env,
	})
	if err != nil {
		return bwStatus{}, fmt.Errorf("%s status: bw %v: %w", label, []string{"status", "--raw"}, err)
	}

	var status bwStatus
	if err := json.Unmarshal(out, &status); err != nil {
		return bwStatus{}, fmt.Errorf("%s status: parse bw status JSON: %w", label, err)
	}
	return status, nil
}

type bwObject struct {
	ID string `json:"id"`
}

func (m Mirror) listObjects(ctx context.Context, kind string, env map[string]string, skipEmptyIDs bool) ([]bwObject, error) {
	out, err := m.Runner.Run(ctx, Command{
		Args: []string{"list", kind},
		Env:  env,
	})
	if err != nil {
		return nil, fmt.Errorf("list destination %s: bw %v: %w", kind, []string{"list", kind}, err)
	}
	var objects []bwObject
	if err := json.Unmarshal(out, &objects); err != nil {
		return nil, fmt.Errorf("parse destination %s JSON before deletion: %w", kind, err)
	}
	filtered := objects[:0]
	for i, object := range objects {
		if object.ID == "" {
			if skipEmptyIDs {
				continue
			}
			return nil, fmt.Errorf("parse destination %s JSON before deletion: object %d has empty id", kind, i)
		}
		filtered = append(filtered, object)
	}
	return filtered, nil
}

func (m Mirror) run(ctx context.Context, phase string, cmd Command) error {
	if _, err := m.Runner.Run(ctx, cmd); err != nil {
		return fmt.Errorf("%s: bw %v: %w", phase, cmd.Args, err)
	}
	return nil
}

func bwEnv(appdataDir string, creds Credentials, session string) map[string]string {
	env := map[string]string{
		"BITWARDENCLI_APPDATA_DIR": appdataDir,
		"BW_CLIENTID":              creds.ClientID,
		"BW_CLIENTSECRET":          creds.ClientSecret,
		"BW_PASSWORD":              creds.MasterPassword,
	}
	if session != "" {
		env["BW_SESSION"] = session
	}
	return env
}

func (c Config) sourceAppdataDir() string {
	return filepath.Join(c.StateDir, "source")
}

func (c Config) destinationAppdataDir() string {
	return filepath.Join(c.StateDir, "destination")
}

func (c Config) destinationDeleteAppdataDir(workerID int) string {
	return filepath.Join(c.WorkDir, "destination-delete", fmt.Sprintf("worker-%d", workerID))
}

func retryBackoff(attempt int) time.Duration {
	if attempt < 1 {
		attempt = 1
	}
	return time.Duration(15*(1<<(attempt-1))) * time.Second
}

func sleepWithContext(ctx context.Context, d time.Duration) error {
	timer := time.NewTimer(d)
	defer timer.Stop()

	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}

func bytesTrimSpace(in []byte) []byte {
	start := 0
	for start < len(in) && (in[start] == ' ' || in[start] == '\n' || in[start] == '\r' || in[start] == '\t') {
		start++
	}
	end := len(in)
	for end > start && (in[end-1] == ' ' || in[end-1] == '\n' || in[end-1] == '\r' || in[end-1] == '\t') {
		end--
	}
	return in[start:end]
}
