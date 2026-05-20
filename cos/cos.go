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

// UploadFile uploads a local file to COS and returns the CDN URL
func (c *COSClient) UploadFile(ctx context.Context, filePath string) (string, error) {
	// Read file
	data, err := os.ReadFile(filePath)
	if err != nil {
		return "", fmt.Errorf("failed to read file: %w", err)
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
		return "", fmt.Errorf("COS upload failed: %w", err)
	}

	// Return CDN URL
	return c.CDNURL(key), nil
}

// CDNURL returns the CDN URL for a given COS key
func (c *COSClient) CDNURL(key string) string {
	if c.cdnDomain == "" {
		return fmt.Sprintf("https://%s.cos.%s.myqcloud.com/%s", c.bucket, c.region, key)
	}
	return fmt.Sprintf("https://%s/%s", c.cdnDomain, key)
}
