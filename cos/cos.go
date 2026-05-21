package cos

import (
	"context"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	"vpaste/config"

	"github.com/tencentyun/cos-go-sdk-v5"
)

type COSClient struct {
	client     *cos.Client
	bucket     string
	region     string
	cdnDomain  string
	uploadPath string
}

func NewCOSClient(cfg *config.Config) (*COSClient, error) {
	bucketURL, _ := url.Parse(fmt.Sprintf("https://%s.cos.%s.myqcloud.com", cfg.Bucket, cfg.Region))
	serviceURL, _ := url.Parse(fmt.Sprintf("https://cos.%s.myqcloud.com", cfg.Region))

	client := cos.NewClient(&cos.BaseURL{
		BucketURL:  bucketURL,
		ServiceURL: serviceURL,
	}, &http.Client{
		Transport: &cos.AuthorizationTransport{
			SecretID:     cfg.SecretID,
			SecretKey:    cfg.SecretKey,
			SessionToken: cfg.Token,
		},
	})

	return &COSClient{
		client:     client,
		bucket:     cfg.Bucket,
		region:     cfg.Region,
		cdnDomain:  cfg.CDNDomain,
		uploadPath: cfg.UploadPath,
	}, nil
}

// UploadResult 上传结果
type UploadResult struct {
	Key    string // COS文件路径
	CDNURL string // CDN访问地址
	Size   int64  // 文件大小
}

// UploadFile uploads a local file to COS and returns the upload result
func (c *COSClient) UploadFile(ctx context.Context, filePath string) (*UploadResult, error) {
	// Read file
	data, err := os.ReadFile(filePath)
	if err != nil {
		return nil, fmt.Errorf("failed to read file: %w", err)
	}

	// Generate key with date path
	now := time.Now()
	datePath := now.Format("2006/01/02")
	filename := filepath.Base(filePath)
	key := fmt.Sprintf("%s/%s/%s", c.uploadPath, datePath, filename)

	// Upload to COS
	reader := strings.NewReader(string(data))
	opt := &cos.ObjectPutOptions{
		ObjectPutHeaderOptions: &cos.ObjectPutHeaderOptions{
			ContentType: "image/png",
		},
	}

	_, err = c.client.Object.Put(ctx, key, reader, opt)
	if err != nil {
		return nil, fmt.Errorf("COS upload failed: %w", err)
	}

	// Return result
	return &UploadResult{
		Key:    key,
		CDNURL: c.CDNURL(key),
		Size:   int64(len(data)),
	}, nil
}

// CDNURL returns the CDN URL for a given COS key
func (c *COSClient) CDNURL(key string) string {
	if c.cdnDomain == "" {
		return fmt.Sprintf("https://%s.cos.%s.myqcloud.com/%s", c.bucket, c.region, key)
	}
	return fmt.Sprintf("https://%s/%s", c.cdnDomain, key)
}

// DeleteFile 删除COS上的文件
func (c *COSClient) DeleteFile(ctx context.Context, key string) error {
	_, err := c.client.Object.Delete(ctx, key)
	if err != nil {
		return fmt.Errorf("failed to delete %s: %w", key, err)
	}
	return nil
}

// CleanupOldFiles 删除指定目录下超过保留时间的文件
// prefix: 目录前缀（如 "vpaste/temp"）
// retentionHours: 保留时间（小时）
func (c *COSClient) CleanupOldFiles(ctx context.Context, prefix string, retentionHours int) (int, error) {
	cutoffTime := time.Now().Add(-time.Duration(retentionHours) * time.Hour)
	deletedCount := 0

	// 列出前缀下的所有对象
	opt := &cos.BucketGetOptions{
		Prefix: prefix,
	}

	result, _, err := c.client.Bucket.Get(ctx, opt)
	if err != nil {
		return 0, fmt.Errorf("failed to list objects: %w", err)
	}

	if len(result.Contents) == 0 {
		return 0, nil
	}

	for _, obj := range result.Contents {
		// 解析最后修改时间
		lastModified, err := time.Parse(time.RFC3339, obj.LastModified)
		if err != nil {
			// 尝试其他格式
			lastModified, err = time.Parse("2006-01-02T15:04:05Z", obj.LastModified)
			if err != nil {
				continue // 跳过无法解析时间的文件
			}
		}

		// 如果文件最后修改时间早于截止时间，则删除
		if lastModified.Before(cutoffTime) {
			_, err := c.client.Object.Delete(ctx, obj.Key)
			if err != nil {
				fmt.Fprintf(os.Stderr, "Warning: failed to delete %s: %v\n", obj.Key, err)
				continue
			}
			deletedCount++
		}
	}

	return deletedCount, nil
}
