package s3client

import (
	"context"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	"vpaste/config"
	"vpaste/storage"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

type S3Client struct {
	client       *s3.Client
	bucket       string
	region       string
	endpoint     string
	cdnDomain    string
	uploadPath   string
	forcePathStyle bool
}

func NewS3Client(cfg *config.Config) (*S3Client, error) {
	resolver := aws.EndpointResolverFunc(func(service, region string) (aws.Endpoint, error) {
		return aws.Endpoint{
			URL:           cfg.Endpoint,
			SigningRegion:  cfg.Region,
		}, nil
	})

	awsCfg, err := awsconfig.LoadDefaultConfig(context.Background(),
		awsconfig.WithRegion(cfg.Region),
		awsconfig.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(
			cfg.SecretID, cfg.SecretKey, cfg.Token,
		)),
		awsconfig.WithEndpointResolver(resolver),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to load AWS config: %w", err)
	}

	client := s3.NewFromConfig(awsCfg, func(o *s3.Options) {
		o.UsePathStyle = cfg.ForcePathStyle
	})

	return &S3Client{
		client:         client,
		bucket:         cfg.Bucket,
		region:         cfg.Region,
		endpoint:       cfg.Endpoint,
		cdnDomain:      cfg.CDNDomain,
		uploadPath:     cfg.UploadPath,
		forcePathStyle: cfg.ForcePathStyle,
	}, nil
}

func (c *S3Client) UploadFile(ctx context.Context, filePath string) (*storage.UploadResult, error) {
	data, err := os.ReadFile(filePath)
	if err != nil {
		return nil, fmt.Errorf("failed to read file: %w", err)
	}

	now := time.Now()
	datePath := now.Format("2006/01/02")
	filename := filepath.Base(filePath)
	key := fmt.Sprintf("%s/%s/%s", c.uploadPath, datePath, filename)

	contentType := "image/png"
	if strings.HasSuffix(strings.ToLower(filename), ".jpg") || strings.HasSuffix(strings.ToLower(filename), ".jpeg") {
		contentType = "image/jpeg"
	}

	_, err = c.client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(c.bucket),
		Key:         aws.String(key),
		Body:        strings.NewReader(string(data)),
		ContentType: aws.String(contentType),
	})
	if err != nil {
		return nil, fmt.Errorf("S3 upload failed: %w", err)
	}

	return &storage.UploadResult{
		Key:    key,
		CDNURL: c.CDNURL(key),
		Size:   int64(len(data)),
	}, nil
}

func (c *S3Client) CDNURL(key string) string {
	if c.cdnDomain != "" {
		return fmt.Sprintf("https://%s/%s", c.cdnDomain, key)
	}
	// Fallback to direct S3 URL
	if c.forcePathStyle {
		parsed, _ := url.Parse(c.endpoint)
		host := parsed.Host
		return fmt.Sprintf("%s://%s/%s/%s", parsed.Scheme, host, c.bucket, key)
	}
	return fmt.Sprintf("https://%s.s3.%s.amazonaws.com/%s", c.bucket, c.region, key)
}

func (c *S3Client) DeleteFile(ctx context.Context, key string) error {
	_, err := c.client.DeleteObject(ctx, &s3.DeleteObjectInput{
		Bucket: aws.String(c.bucket),
		Key:    aws.String(key),
	})
	if err != nil {
		return fmt.Errorf("failed to delete %s: %w", key, err)
	}
	return nil
}
