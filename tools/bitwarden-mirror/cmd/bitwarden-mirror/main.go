package main

import (
	"context"
	"flag"
	"log"
	"os"

	"alcachofa.faith/lab/tools/bitwarden-mirror/internal/mirror"
)

func main() {
	var cfg mirror.Config
	flag.StringVar(&cfg.SourceServer, "source-server", "https://vault.bitwarden.eu", "source Bitwarden server URL")
	flag.StringVar(&cfg.DestinationServer, "destination-server", "https://vault.alcachofa.faith", "destination Vaultwarden server URL")
	flag.StringVar(&cfg.WorkDir, "work-dir", "/run/bitwarden-mirror", "directory for temporary plaintext export")
	flag.StringVar(&cfg.StateDir, "state-dir", "/var/lib/bitwarden-mirror", "directory for isolated bw CLI appdata")
	flag.BoolVar(&cfg.DryRun, "dry-run", false, "log planned destructive changes without deleting or importing")
	flag.Parse()

	env, err := mirror.EnvironmentFromEnv()
	if err != nil {
		log.Fatal(err)
	}

	logger := log.New(os.Stdout, "bitwarden-mirror: ", log.LstdFlags|log.LUTC)
	if err := (mirror.Mirror{
		Config: cfg,
		Env:    env,
		Runner: mirror.ExecRunner{},
		Files:  mirror.DefaultFileOps(),
		Logger: logger,
	}).Run(context.Background()); err != nil {
		log.Fatal(err)
	}
}
