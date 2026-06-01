package mirror

import (
	"context"
	"errors"
	"io"
	"log"
	"os"
	"reflect"
	"strings"
	"testing"
)

func TestRunCommandOrderDeletesItemsBeforeFoldersAndImports(t *testing.T) {
	runner := newFakeRunner()
	runner.outputs = map[string][]byte{
		"unlock --raw --passwordenv BW_PASSWORD": []byte("session\n"),
		"list items":                             []byte(`[{"id":"item-1"},{"id":"item-2"}]`),
		"list folders":                           []byte(`[{"id":"folder-1"}]`),
	}

	err := testMirror(runner, nil, false).Run(context.Background())
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}

	want := []string{
		"logout",
		"config server https://vault.bitwarden.eu",
		"login --apikey",
		"unlock --raw --passwordenv BW_PASSWORD",
		"sync",
		"export --format json --output /work/bitwarden-export.json",
		"logout",
		"config server https://vault.alcachofa.faith",
		"login --apikey",
		"unlock --raw --passwordenv BW_PASSWORD",
		"list items",
		"list folders",
		"delete item item-1 --permanent",
		"delete item item-2 --permanent",
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
	destinationConfig := runner.calls[6]
	if got := destinationConfig.Env["BITWARDENCLI_APPDATA_DIR"]; got != "/state/destination" {
		t.Fatalf("destination appdata = %q", got)
	}
}

func TestMalformedListJSONFailsBeforeDeletion(t *testing.T) {
	runner := newFakeRunner()
	runner.outputs = map[string][]byte{
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
		"unlock --raw --passwordenv BW_PASSWORD": []byte("session\n"),
		"list items":                             []byte(`[{"id":"item-1"}]`),
		"list folders":                           []byte(`[]`),
	}

	err := testMirror(runner, nil, true).Run(context.Background())
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}
}

func testMirror(runner *fakeRunner, files *FileOps, dryRun bool) Mirror {
	m := Mirror{
		Config: Config{
			WorkDir:  "/work",
			StateDir: "/state",
			DryRun:   dryRun,
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
	return &FileOps{
		MkdirAll: func(path string, _ os.FileMode) error {
			return nil
		},
		Remove: func(path string) error {
			*removed = append(*removed, path)
			return nil
		},
	}
}

type fakeRunner struct {
	calls    []Command
	outputs  map[string][]byte
	failures map[string]error
}

func newFakeRunner() *fakeRunner {
	return &fakeRunner{
		outputs:  map[string][]byte{},
		failures: map[string]error{},
	}
}

func (r *fakeRunner) Run(_ context.Context, cmd Command) ([]byte, error) {
	r.calls = append(r.calls, cmd)
	line := strings.Join(cmd.Args, " ")
	if err, ok := r.failures[line]; ok {
		return nil, err
	}
	if out, ok := r.outputs[line]; ok {
		return out, nil
	}
	return []byte("ok"), nil
}

func (r *fakeRunner) commandLines() []string {
	lines := make([]string, 0, len(r.calls))
	for _, call := range r.calls {
		lines = append(lines, strings.Join(call.Args, " "))
	}
	return lines
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
