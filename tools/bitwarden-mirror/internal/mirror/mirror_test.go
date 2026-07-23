package mirror

import (
	"context"
	"errors"
	"io"
	"log"
	"os"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestRunCommandOrderDeletesItemsBeforeFoldersAndImports(t *testing.T) {
	runner := newFakeRunner()
	runner.outputs = map[string][]byte{
		"status --raw":                           []byte(`{"status":"unauthenticated"}`),
		"unlock --raw --passwordenv BW_PASSWORD": []byte("session\n"),
		"list items":                             []byte(`[{"id":"item-1"},{"id":"item-2"}]`),
		"list folders":                           []byte(`[{"id":"folder-1"}]`),
	}

	err := testMirror(runner, nil, false).Run(context.Background())
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}

	want := []string{
		"status --raw",
		"config server https://vault.bitwarden.eu",
		"login --apikey",
		"unlock --raw --passwordenv BW_PASSWORD",
		"sync",
		"export --format json --output /work/bitwarden-export.json",
		"status --raw",
		"config server https://vault.alcachofa.faith",
		"login --apikey",
		"unlock --raw --passwordenv BW_PASSWORD",
		"list items",
		"list folders",
		"status --raw",
		"config server https://vault.alcachofa.faith",
		"login --apikey",
		"unlock --raw --passwordenv BW_PASSWORD",
		"delete item item-1 --permanent",
		"delete item item-2 --permanent",
		"status --raw",
		"config server https://vault.alcachofa.faith",
		"login --apikey",
		"unlock --raw --passwordenv BW_PASSWORD",
		"delete folder folder-1 --permanent",
		"import bitwardenjson /work/bitwarden-export.json",
	}
	if got := runner.commandLines(); !reflect.DeepEqual(got, want) {
		t.Fatalf("commands mismatch\ngot:  %v\nwant: %v", got, want)
	}
}

func TestDryRunDoesNotDeleteOrImport(t *testing.T) {
	runner := newFakeRunner()
	runner.outputs = map[string][]byte{
		"status --raw":                           []byte(`{"status":"unauthenticated"}`),
		"unlock --raw --passwordenv BW_PASSWORD": []byte("session\n"),
		"list items":                             []byte(`[{"id":"item-1"}]`),
		"list folders":                           []byte(`[{"id":"folder-1"}]`),
	}

	err := testMirror(runner, nil, true).Run(context.Background())
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}

	for _, line := range runner.commandLines() {
		if strings.HasPrefix(line, "delete ") || strings.HasPrefix(line, "import ") {
			t.Fatalf("dry run issued mutating command %q", line)
		}
	}
}

func TestEmptyDestinationStillImports(t *testing.T) {
	runner := newFakeRunner()
	runner.outputs = map[string][]byte{
		"status --raw":                           []byte(`{"status":"unauthenticated"}`),
		"unlock --raw --passwordenv BW_PASSWORD": []byte("session\n"),
		"list items":                             []byte(`[]`),
		"list folders":                           []byte(`[]`),
	}

	err := testMirror(runner, nil, false).Run(context.Background())
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}

	if !contains(runner.commandLines(), "import bitwardenjson /work/bitwarden-export.json") {
		t.Fatalf("expected import command, got %v", runner.commandLines())
	}
}

func TestCommandFailureStopsRunWithContext(t *testing.T) {
	runner := newFakeRunner()
	runner.outputs = map[string][]byte{
		"status --raw":                           []byte(`{"status":"unauthenticated"}`),
		"unlock --raw --passwordenv BW_PASSWORD": []byte("session\n"),
	}
	runner.failures = map[string]error{
		"export --format json --output /work/bitwarden-export.json": errors.New("boom"),
	}

	err := testMirror(runner, nil, false).Run(context.Background())
	if err == nil {
		t.Fatal("Run() error = nil")
	}
	if !strings.Contains(err.Error(), "source export") || !strings.Contains(err.Error(), "boom") {
		t.Fatalf("Run() error = %v, want source export context and underlying error", err)
	}
	if containsPrefix(runner.commandLines(), "config server https://vault.alcachofa.faith") {
		t.Fatalf("run continued after source export failure: %v", runner.commandLines())
	}
}

func TestCleanupAttemptedOnSuccessAndFailure(t *testing.T) {
	for _, tc := range []struct {
		name     string
		failures map[string]error
	}{
		{name: "success"},
		{
			name: "failure",
			failures: map[string]error{
				"delete item item-1 --permanent": errors.New("delete failed"),
			},
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			runner := newFakeRunner()
			runner.outputs = map[string][]byte{
				"status --raw":                           []byte(`{"status":"unauthenticated"}`),
				"unlock --raw --passwordenv BW_PASSWORD": []byte("session\n"),
				"list items":                             []byte(`[{"id":"item-1"}]`),
				"list folders":                           []byte(`[]`),
			}
			runner.failures = tc.failures
			removed := []string{}
			files := testFiles(&removed)

			_ = testMirror(runner, files, false).Run(context.Background())

			if !contains(removed, "/work/bitwarden-export.json") {
				t.Fatalf("cleanup was not attempted, removed=%v", removed)
			}
		})
	}
}

func TestSeparateSourceAndDestinationAppdataDirs(t *testing.T) {
	runner := newFakeRunner()
	runner.outputs = map[string][]byte{
		"status --raw":                           []byte(`{"status":"unauthenticated"}`),
		"unlock --raw --passwordenv BW_PASSWORD": []byte("session\n"),
		"list items":                             []byte(`[]`),
		"list folders":                           []byte(`[]`),
	}

	err := testMirror(runner, nil, false).Run(context.Background())
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}

	if got := runner.calls[0].Env["BITWARDENCLI_APPDATA_DIR"]; got != "/state/source" {
		t.Fatalf("source appdata = %q", got)
	}
	destinationConfig := runner.calls[7]
	if got := destinationConfig.Env["BITWARDENCLI_APPDATA_DIR"]; got != "/state/destination" {
		t.Fatalf("destination appdata = %q", got)
	}
}

func TestParallelDeletesUseIsolatedWorkerAppdataDirs(t *testing.T) {
	runner := newFakeRunner()
	runner.outputs = map[string][]byte{
		"status --raw":                           []byte(`{"status":"unauthenticated"}`),
		"unlock --raw --passwordenv BW_PASSWORD": []byte("session\n"),
		"list items":                             []byte(`[{"id":"item-1"},{"id":"item-2"},{"id":"item-3"}]`),
		"list folders":                           []byte(`[]`),
	}

	m := testMirror(runner, nil, false)
	m.Config.DeleteConcurrency = 3
	err := m.Run(context.Background())
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}

	deleteDirs := map[string]bool{}
	for _, call := range runner.snapshotCalls() {
		if len(call.Args) > 0 && call.Args[0] == "delete" {
			deleteDirs[call.Env["BITWARDENCLI_APPDATA_DIR"]] = true
		}
	}
	for got := range deleteDirs {
		if !strings.HasPrefix(got, "/work/destination-delete/worker-") {
			t.Fatalf("delete used non-worker appdata %q; got %v", got, deleteDirs)
		}
	}
	if deleteDirs["/state/destination"] {
		t.Fatalf("delete used shared destination appdata: %v", deleteDirs)
	}
}

func TestDeleteWorkersArePreparedBeforeDeleting(t *testing.T) {
	runner := newFakeRunner()
	runner.outputs = map[string][]byte{
		"status --raw":                           []byte(`{"status":"unauthenticated"}`),
		"unlock --raw --passwordenv BW_PASSWORD": []byte("session\n"),
		"list items":                             []byte(`[{"id":"item-1"},{"id":"item-2"},{"id":"item-3"}]`),
		"list folders":                           []byte(`[]`),
	}

	m := testMirror(runner, nil, false)
	m.Config.DeleteConcurrency = 3
	err := m.Run(context.Background())
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}

	lines := runner.commandLines()
	firstDelete := indexPrefix(lines, "delete ")
	if firstDelete == -1 {
		t.Fatalf("no delete command issued: %v", lines)
	}
	unlocksBeforeDelete := 0
	for _, line := range lines[:firstDelete] {
		if line == "unlock --raw --passwordenv BW_PASSWORD" {
			unlocksBeforeDelete++
		}
	}
	if unlocksBeforeDelete != 5 {
		t.Fatalf("unlocks before first delete = %d, want 5; commands=%v", unlocksBeforeDelete, lines)
	}
}

func TestDeleteWorkersContinueWhenOneWorkerCannotStart(t *testing.T) {
	runner := newFakeRunner()
	runner.outputs = map[string][]byte{
		"status --raw":                           []byte(`{"status":"unauthenticated"}`),
		"unlock --raw --passwordenv BW_PASSWORD": []byte("session\n"),
		"list items":                             []byte(`[{"id":"item-1"},{"id":"item-2"},{"id":"item-3"}]`),
		"list folders":                           []byte(`[]`),
	}

	removed := []string{}
	files := testFilesWithRemoveAll(&removed, nil)
	originalMkdirAll := files.MkdirAll
	files.MkdirAll = func(path string, perm os.FileMode) error {
		if path == "/work/destination-delete/worker-1" {
			return errors.New("mkdir failed")
		}
		return originalMkdirAll(path, perm)
	}

	m := testMirror(runner, files, false)
	m.Config.DeleteConcurrency = 3
	err := m.Run(context.Background())
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}

	deleteDirs := map[string]bool{}
	for _, call := range runner.snapshotCalls() {
		if len(call.Args) > 0 && call.Args[0] == "delete" {
			deleteDirs[call.Env["BITWARDENCLI_APPDATA_DIR"]] = true
		}
	}
	if deleteDirs["/work/destination-delete/worker-1"] {
		t.Fatalf("delete used failed worker appdata: %v", deleteDirs)
	}
	if len(deleteDirs) != 2 {
		t.Fatalf("delete used %d worker dirs, want 2; got %v", len(deleteDirs), deleteDirs)
	}
}

func TestDeleteWorkersFailWhenNoneCanStart(t *testing.T) {
	runner := newFakeRunner()
	runner.outputs = map[string][]byte{
		"status --raw":                           []byte(`{"status":"unauthenticated"}`),
		"unlock --raw --passwordenv BW_PASSWORD": []byte("session\n"),
		"list items":                             []byte(`[{"id":"item-1"}]`),
		"list folders":                           []byte(`[]`),
	}

	removed := []string{}
	files := testFilesWithRemoveAll(&removed, nil)
	files.MkdirAll = func(path string, _ os.FileMode) error {
		if strings.HasPrefix(path, "/work/destination-delete/worker-") {
			return errors.New("mkdir failed")
		}
		return nil
	}

	m := testMirror(runner, files, false)
	err := m.Run(context.Background())
	if err == nil {
		t.Fatal("Run() error = nil")
	}
	if !strings.Contains(err.Error(), "prepare destination delete workers") {
		t.Fatalf("Run() error = %v", err)
	}
	if containsPrefix(runner.commandLines(), "delete ") {
		t.Fatalf("delete commands should not run when all workers fail: %v", runner.commandLines())
	}
}

func TestMalformedListJSONFailsBeforeDeletion(t *testing.T) {
	runner := newFakeRunner()
	runner.outputs = map[string][]byte{
		"status --raw":                           []byte(`{"status":"unauthenticated"}`),
		"unlock --raw --passwordenv BW_PASSWORD": []byte("session\n"),
		"list items":                             []byte(`not-json`),
	}

	err := testMirror(runner, nil, false).Run(context.Background())
	if err == nil {
		t.Fatal("Run() error = nil")
	}
	if !strings.Contains(err.Error(), "parse destination items JSON before deletion") {
		t.Fatalf("Run() error = %v, want parse-before-deletion context", err)
	}
	if containsPrefix(runner.commandLines(), "delete ") || containsPrefix(runner.commandLines(), "import ") {
		t.Fatalf("mutating command issued after malformed JSON: %v", runner.commandLines())
	}
}

func TestFolderListSkipsEmptyIDs(t *testing.T) {
	runner := newFakeRunner()
	runner.outputs = map[string][]byte{
		"status --raw":                           []byte(`{"status":"unauthenticated"}`),
		"unlock --raw --passwordenv BW_PASSWORD": []byte("session\n"),
		"list items":                             []byte(`[]`),
		"list folders":                           []byte(`[{"id":null},{"id":"folder-1"}]`),
	}

	err := testMirror(runner, nil, false).Run(context.Background())
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}
	if contains(runner.commandLines(), "delete folder  --permanent") {
		t.Fatalf("issued delete for empty folder id: %v", runner.commandLines())
	}
	if !contains(runner.commandLines(), "delete folder folder-1 --permanent") {
		t.Fatalf("did not delete valid folder id: %v", runner.commandLines())
	}
}

func TestListIgnoresRunnerStderrOnSuccess(t *testing.T) {
	runner := newFakeRunner()
	runner.outputs = map[string][]byte{
		"status --raw":                           []byte(`{"status":"unauthenticated"}`),
		"unlock --raw --passwordenv BW_PASSWORD": []byte("session\n"),
		"list items":                             []byte(`[{"id":"item-1"}]`),
		"list folders":                           []byte(`[]`),
	}

	err := testMirror(runner, nil, true).Run(context.Background())
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}
}

func TestExistingLoginSkipsConfigureAndLogin(t *testing.T) {
	runner := newFakeRunner()
	runner.outputs = map[string][]byte{
		"status --raw":                           []byte(`{"status":"locked"}`),
		"unlock --raw --passwordenv BW_PASSWORD": []byte("session\n"),
		"list items":                             []byte(`[]`),
		"list folders":                           []byte(`[]`),
	}

	err := testMirror(runner, nil, true).Run(context.Background())
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}

	lines := runner.commandLines()
	if containsPrefix(lines, "config server ") || contains(lines, "login --apikey") {
		t.Fatalf("expected existing login to skip config/login, got %v", lines)
	}
}

func TestLoginUnlockWithRecoveryClearsAppdataAfterEmptySession(t *testing.T) {
	runner := newFakeRunner()
	runner.outputs = map[string][]byte{
		"status --raw": []byte(`{"status":"locked"}`),
	}
	runner.sequenceOutputs = map[string][][]byte{
		"unlock --raw --passwordenv BW_PASSWORD": {
			[]byte(""),
			[]byte("session\n"),
		},
	}

	removed := []string{}
	removedDirs := []string{}
	slept := []time.Duration{}
	files := testFilesWithRemoveAll(&removed, &removedDirs)
	m := testMirror(runner, files, true)
	m.Sleep = func(_ context.Context, d time.Duration) error {
		slept = append(slept, d)
		return nil
	}

	session, err := m.loginUnlockWithRecovery(
		context.Background(),
		"destination delete worker",
		"https://vault.alcachofa.faith",
		"/work/destination-delete/worker-7",
		m.Env.Destination,
		m.Files,
		m.Logger,
		m.Sleep,
	)
	if err != nil {
		t.Fatalf("loginUnlockWithRecovery() error = %v", err)
	}
	if session != "session" {
		t.Fatalf("session = %q", session)
	}
	if !contains(removedDirs, "/work/destination-delete/worker-7") {
		t.Fatalf("expected appdata reset, removedDirs=%v", removedDirs)
	}
	if len(slept) != 1 || slept[0] != 15*time.Second {
		t.Fatalf("sleep calls = %v, want [15s]", slept)
	}
}

func TestLoginUnlockWithRecoveryRetriesRateLimitWithoutResettingAppdata(t *testing.T) {
	runner := newFakeRunner()
	runner.outputs = map[string][]byte{
		"status --raw":                           []byte(`{"status":"unauthenticated"}`),
		"unlock --raw --passwordenv BW_PASSWORD": []byte("session\n"),
	}
	runner.sequenceFailures = map[string][]error{
		"login --apikey": {
			errors.New("Rate limit exceeded. Try again later."),
			nil,
		},
	}

	removed := []string{}
	removedDirs := []string{}
	slept := []time.Duration{}
	files := testFilesWithRemoveAll(&removed, &removedDirs)
	m := testMirror(runner, files, true)
	m.Sleep = func(_ context.Context, d time.Duration) error {
		slept = append(slept, d)
		return nil
	}

	session, err := m.loginUnlockWithRecovery(
		context.Background(),
		"source",
		"https://vault.bitwarden.eu",
		"/state/source",
		m.Env.Source,
		m.Files,
		m.Logger,
		m.Sleep,
	)
	if err != nil {
		t.Fatalf("loginUnlockWithRecovery() error = %v", err)
	}
	if session != "session" {
		t.Fatalf("session = %q", session)
	}
	if len(removedDirs) != 0 {
		t.Fatalf("did not expect appdata reset, removedDirs=%v", removedDirs)
	}
	if len(slept) != 1 || slept[0] != time.Minute {
		t.Fatalf("sleep calls = %v, want [1m0s]", slept)
	}
}

func testMirror(runner *fakeRunner, files *FileOps, dryRun bool) Mirror {
	m := Mirror{
		Config: Config{
			WorkDir:           "/work",
			StateDir:          "/state",
			DryRun:            dryRun,
			DeleteConcurrency: 1,
		},
		Env: Environment{
			Source: Credentials{
				ClientID:       "source-id",
				ClientSecret:   "source-secret",
				MasterPassword: "source-password",
			},
			Destination: Credentials{
				ClientID:       "dest-id",
				ClientSecret:   "dest-secret",
				MasterPassword: "dest-password",
			},
		},
		Runner: runner,
		Logger: log.New(io.Discard, "", 0),
	}
	if files != nil {
		m.Files = *files
	} else {
		removed := []string{}
		m.Files = *testFiles(&removed)
	}
	return m
}

func testFiles(removed *[]string) *FileOps {
	return testFilesWithRemoveAll(removed, nil)
}

func testFilesWithRemoveAll(removed *[]string, removedDirs *[]string) *FileOps {
	return &FileOps{
		MkdirAll: func(path string, _ os.FileMode) error {
			return nil
		},
		Remove: func(path string) error {
			*removed = append(*removed, path)
			return nil
		},
		RemoveAll: func(path string) error {
			if removedDirs != nil {
				*removedDirs = append(*removedDirs, path)
			}
			return nil
		},
	}
}

type fakeRunner struct {
	mu               sync.Mutex
	calls            []Command
	outputs          map[string][]byte
	failures         map[string]error
	sequenceOutputs  map[string][][]byte
	sequenceFailures map[string][]error
}

func newFakeRunner() *fakeRunner {
	return &fakeRunner{
		outputs:          map[string][]byte{},
		failures:         map[string]error{},
		sequenceOutputs:  map[string][][]byte{},
		sequenceFailures: map[string][]error{},
	}
}

func (r *fakeRunner) Run(_ context.Context, cmd Command) ([]byte, error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	r.calls = append(r.calls, cmd)
	line := strings.Join(cmd.Args, " ")
	if outputs, ok := r.sequenceOutputs[line]; ok && len(outputs) > 0 {
		out := outputs[0]
		r.sequenceOutputs[line] = outputs[1:]
		return out, nil
	}
	if failures, ok := r.sequenceFailures[line]; ok && len(failures) > 0 {
		err := failures[0]
		r.sequenceFailures[line] = failures[1:]
		if err != nil {
			return nil, err
		}
	}
	if err, ok := r.failures[line]; ok {
		return nil, err
	}
	if out, ok := r.outputs[line]; ok {
		return out, nil
	}
	return []byte("ok"), nil
}

func (r *fakeRunner) commandLines() []string {
	calls := r.snapshotCalls()
	lines := make([]string, 0, len(calls))
	for _, call := range calls {
		lines = append(lines, strings.Join(call.Args, " "))
	}
	return lines
}

func (r *fakeRunner) snapshotCalls() []Command {
	r.mu.Lock()
	defer r.mu.Unlock()
	return append([]Command(nil), r.calls...)
}

func contains(values []string, want string) bool {
	for _, value := range values {
		if value == want {
			return true
		}
	}
	return false
}

func containsPrefix(values []string, prefix string) bool {
	for _, value := range values {
		if strings.HasPrefix(value, prefix) {
			return true
		}
	}
	return false
}

func indexPrefix(values []string, prefix string) int {
	for i, value := range values {
		if strings.HasPrefix(value, prefix) {
			return i
		}
	}
	return -1
}
