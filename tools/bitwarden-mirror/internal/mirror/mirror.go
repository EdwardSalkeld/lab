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
)

const (
	defaultSourceServer      = "https://vault.bitwarden.eu"
	defaultDestinationServer = "https://vault.alcachofa.faith"
	defaultWorkDir           = "/run/bitwarden-mirror"
	defaultStateDir          = "/var/lib/bitwarden-mirror"
)

type Config struct {
	SourceServer      string
	DestinationServer string
	WorkDir           string
	StateDir          string
	DryRun            bool
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
	MkdirAll func(path string, perm os.FileMode) error
	Remove   func(path string) error
}

func DefaultFileOps() FileOps {
	return FileOps{
		MkdirAll: os.MkdirAll,
		Remove:   os.Remove,
	}
}

type Mirror struct {
	Config Config
	Env    Environment
	Runner Runner
	Files  FileOps
	Logger *log.Logger
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
	logger := m.Logger
	if logger == nil {
		logger = log.New(io.Discard, "", 0)
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

	if _, err := m.loginUnlockSyncExport(ctx, "source", cfg.SourceServer, cfg.sourceAppdataDir(), m.Env.Source, exportPath); err != nil {
		return err
	}

	destSession, err := m.loginUnlock(ctx, "destination", cfg.DestinationServer, cfg.destinationAppdataDir(), m.Env.Destination)
	if err != nil {
		return err
	}

	destEnv := bwEnv(cfg.destinationAppdataDir(), m.Env.Destination, destSession)
	items, err := m.listObjects(ctx, "items", destEnv)
	if err != nil {
		return err
	}
	folders, err := m.listObjects(ctx, "folders", destEnv)
	if err != nil {
		return err
	}

	if cfg.DryRun {
		logger.Printf("dry run: would permanently delete %d destination items and %d folders", len(items), len(folders))
		logger.Printf("dry run: would import %s into destination", exportPath)
		return nil
	}

	for _, item := range items {
		if err := m.run(ctx, "delete destination item", Command{
			Args: []string{"delete", "item", item.ID, "--permanent"},
			Env:  destEnv,
		}); err != nil {
			return err
		}
	}
	for _, folder := range folders {
		if err := m.run(ctx, "delete destination folder", Command{
			Args: []string{"delete", "folder", folder.ID, "--permanent"},
			Env:  destEnv,
		}); err != nil {
			return err
		}
	}

	if err := m.run(ctx, "import destination vault", Command{
		Args: []string{"import", "bitwardenjson", exportPath},
		Env:  destEnv,
	}); err != nil {
		return err
	}

	if err := cleanup(); err != nil {
		return err
	}
	return nil
}

func (m Mirror) loginUnlockSyncExport(ctx context.Context, label, server, appdataDir string, creds Credentials, exportPath string) (string, error) {
	session, err := m.loginUnlock(ctx, label, server, appdataDir, creds)
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

func (m Mirror) loginUnlock(ctx context.Context, label, server, appdataDir string, creds Credentials) (string, error) {
	env := bwEnv(appdataDir, creds, "")
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

type bwObject struct {
	ID string `json:"id"`
}

func (m Mirror) listObjects(ctx context.Context, kind string, env map[string]string) ([]bwObject, error) {
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
	for i, object := range objects {
		if object.ID == "" {
			return nil, fmt.Errorf("parse destination %s JSON before deletion: object %d has empty id", kind, i)
		}
	}
	return objects, nil
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
