package config

import (
	"fmt"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"
)

type Config struct {
	SecretID           string `yaml:"secret_id"`
	SecretKey          string `yaml:"secret_key"`
	Token              string `yaml:"token"`
	Bucket             string `yaml:"bucket"`
	Region             string `yaml:"region"`
	CDNDomain          string `yaml:"cdn_domain"`
	UploadPath         string `yaml:"upload_path"`
	TempRetentionHours int    `yaml:"temp_retention_hours"` // 临时文件保留时间（小时），默认24
}

func Load() (*Config, error) {
	configPath := configFilePath()

	data, err := os.ReadFile(configPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read config file: %w\nplease create config at: %s", err, configPath)
	}

	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("failed to parse config: %w", err)
	}

	if cfg.SecretID == "" || cfg.SecretKey == "" || cfg.Bucket == "" || cfg.Region == "" {
		return nil, fmt.Errorf("missing required fields: secret_id, secret_key, bucket, region")
	}

	if cfg.UploadPath == "" {
		cfg.UploadPath = "vpaste/temp"
	}
	if cfg.TempRetentionHours <= 0 {
		cfg.TempRetentionHours = 24 // 默认保留24小时
	}

	return &cfg, nil
}

func configFilePath() string {
	// Check VPASTE_CONFIG env var first
	if envPath := os.Getenv("VPASTE_CONFIG"); envPath != "" {
		return envPath
	}
	// Default path
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".config", "vpaste", "config.yaml")
}

func ConfigFilePath() string {
	return configFilePath()
}
