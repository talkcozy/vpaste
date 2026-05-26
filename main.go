package main

import (
	"context"
	"fmt"
	"os"

	"vpaste/clipboard"
	"vpaste/config"
	"vpaste/cos"
	"vpaste/db"
)

func main() {
	// 检查子命令
	if len(os.Args) > 1 && os.Args[1] == "clean" {
		hours := 0
		if len(os.Args) > 2 {
			fmt.Sscanf(os.Args[2], "%d", &hours)
		}
		if err := runClean(hours); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
		return
	}

	if len(os.Args) > 1 && os.Args[1] == "stats" {
		if err := runStats(); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
		return
	}

	if err := runUpload(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

func runUpload() error {
	// Load config
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("config error: %w", err)
	}

	// 初始化数据库
	database, err := db.New("")
	if err != nil {
		return fmt.Errorf("db error: %w", err)
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
	result, err := client.UploadFile(ctx, imagePath)
	if err != nil {
		return fmt.Errorf("upload error: %w", err)
	}

	// 记录上传
	if err := database.AddRecord(result.Key, result.CDNURL, result.Size); err != nil {
		// 记录失败不影响上传，只是打印警告
		fmt.Fprintf(os.Stderr, "Warning: failed to record upload: %v\n", err)
	}

	// 异步清理旧文件（不阻塞上传流程）
	if database.ShouldClean() {
		go cleanupOldFiles(ctx, client, database, cfg.TempRetentionHours)
	}

	// Output URL to stdout only
	fmt.Print(result.CDNURL)

	return nil
}

// cleanupOldFiles 异步清理旧文件
func cleanupOldFiles(ctx context.Context, client *cos.COSClient, database *db.DB, retentionHours int) {
	// 标记已经开始清理，避免重复执行
	database.MarkCleaned()

	records := database.GetRecordsToClean(retentionHours)
	if len(records) == 0 {
		return
	}

	var deletedKeys []string
	for _, r := range records {
		err := client.DeleteFile(ctx, r.Key)
		if err != nil {
			// 清理失败不影响其他文件
			continue
		}
		deletedKeys = append(deletedKeys, r.Key)
	}

	// 从记录中删除已清理的文件
	if len(deletedKeys) > 0 {
		database.RemoveRecords(deletedKeys)
	}
}

func runClean(hoursOverride int) error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("config error: %w", err)
	}

	client, err := cos.NewCOSClient(cfg)
	if err != nil {
		return fmt.Errorf("COS client error: %w", err)
	}

	database, err := db.New("")
	if err != nil {
		return fmt.Errorf("db error: %w", err)
	}

	ctx := context.Background()
	hours := cfg.TempRetentionHours
	if hoursOverride > 0 {
		hours = hoursOverride
	}

	fmt.Printf("Cleaning up files older than %d hours...\n", hours)

	cleanupOldFiles(ctx, client, database, hours)

	count, oldest, _ := database.Stats()
	fmt.Printf("Remaining records: %d", count)
	if !oldest.IsZero() {
		fmt.Printf(" (oldest: %s)", oldest.Format("2006-01-02 15:04"))
	}
	fmt.Println()

	return nil
}

func runStats() error {
	database, err := db.New("")
	if err != nil {
		return fmt.Errorf("db error: %w", err)
	}

	count, oldest, lastClean := database.Stats()
	fmt.Printf("Total uploads: %d\n", count)
	if !oldest.IsZero() {
		fmt.Printf("Oldest record: %s\n", oldest.Format("2006-01-02 15:04:05"))
	}
	if lastClean.IsZero() {
		fmt.Printf("Last clean: never\n")
	} else {
		fmt.Printf("Last clean: %s\n", lastClean.Format("2006-01-02 15:04:05"))
	}

	return nil
}