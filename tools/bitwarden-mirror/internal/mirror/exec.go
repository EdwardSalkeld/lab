package mirror

import (
	"context"
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
	return execCmd.CombinedOutput()
}
