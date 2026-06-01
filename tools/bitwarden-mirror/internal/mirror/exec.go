package mirror

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
)

type ExecRunner struct{}

func (ExecRunner) Run(ctx context.Context, cmd Command) ([]byte, error) {
	execCmd := exec.CommandContext(ctx, "bw", cmd.Args...)
	execCmd.Env = os.Environ()
	for key, value := range cmd.Env {
		execCmd.Env = append(execCmd.Env, key+"="+value)
	}

	var stdout bytes.Buffer
	var stderr bytes.Buffer
	execCmd.Stdout = &stdout
	execCmd.Stderr = &stderr
	if err := execCmd.Run(); err != nil {
		if stderr.Len() > 0 {
			return stdout.Bytes(), fmt.Errorf("%w: %s", err, bytesTrimSpace(stderr.Bytes()))
		}
		return stdout.Bytes(), err
	}
	return stdout.Bytes(), nil
}
