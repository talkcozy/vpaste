package main

import (
	"context"
	"fmt"
	"os"

	"vpaste/clipboard"
	"vpaste/config"
	"vpaste/cos"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	// Load config
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("config error: %w", err)
	}

	// Get image from clipboard
	imagePath, err := clipboard.GetImageFromClipboard()
	if err != nil {
		return fmt.Errorf("clipboard error: %w", err)
	}
	if imagePath == "" {
		// No image in clipboard, output special message
		fmt.Print("NO_IMAGE")
		return nil
	}
	defer clipboard.CleanupTempFile(imagePath)

	// Upload to COS
	client, err := cos.NewCOSClient(cfg)
	if err != nil {
		return fmt.Errorf("COS client error: %w", err)
	}

	ctx := context.Background()
	cdnURL, err := client.UploadFile(ctx, imagePath)
	if err != nil {
		return fmt.Errorf("upload error: %w", err)
	}

	// Output URL to stdout only
	fmt.Print(cdnURL)

	return nil
}