package clipboard

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const TempDir = "/tmp/vpaste"

// GetImageFromClipboard saves clipboard image to temp file and returns the path.
// Returns empty string if no image in clipboard.
func GetImageFromClipboard() (string, error) {
	// Ensure temp dir exists
	if err := os.MkdirAll(TempDir, 0755); err != nil {
		return "", fmt.Errorf("failed to create temp dir: %w", err)
	}

	// Generate filename with timestamp
	timestamp := time.Now().Unix()
	tempPath := filepath.Join(TempDir, fmt.Sprintf("%d.png", timestamp))

	// Use macOS osascript to get image from clipboard
	// Try TIFF first (most common), then PNG, then JPEG
	script := fmt.Sprintf(`
		try
			set theImage to the clipboard as TIFF picture
			set fp to open for access POSIX file "%s" with write permission
			write theImage to fp
			close access fp
		on error
			try
				set theImage to the clipboard as «class PNGf»
				set fp to open for access POSIX file "%s" with write permission
				write theImage to fp
				close access fp
			on error
				try
					set theImage to the clipboard as JPEG picture
					set fp to open for access POSIX file "%s" with write permission
					write theImage to fp
					close access fp
				on error
					return "NO_IMAGE"
				end try
			end try
		end try
	`, tempPath, tempPath, tempPath)

	cmd := exec.Command("osascript", "-e", script)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("osascript failed: %w, output: %s", err, output)
	}

	// Check if we got NO_IMAGE
	outputStr := string(output)
	if outputStr == "NO_IMAGE\n" || outputStr == "NO_IMAGE" || strings.Contains(outputStr, "NO_IMAGE") {
		return "", nil
	}

	// Verify file exists and has content
	info, err := os.Stat(tempPath)
	if err != nil {
		return "", nil // No image in clipboard
	}
	if info.Size() < 100 {
		os.Remove(tempPath)
		return "", nil
	}

	// Convert to PNG format using sips (macOS built-in)
	// This ensures the file is a proper PNG, not TIFF with .png extension
	convertCmd := exec.Command("sips", "-s", "format", "png", tempPath, "--out", tempPath)
	if err := convertCmd.Run(); err != nil {
		return "", fmt.Errorf("failed to convert image to PNG: %w", err)
	}

	return tempPath, nil
}

// CleanupTempFile removes the temp file
func CleanupTempFile(path string) {
	if path != "" {
		os.Remove(path)
	}
}
