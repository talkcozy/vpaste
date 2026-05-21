package db

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// UploadRecord 记录单次上传的文件信息
type UploadRecord struct {
	Key        string    `json:"key"`         // COS文件路径
	CDNURL     string    `json:"cdn_url"`     // CDN访问地址
	UploadedAt time.Time `json:"uploaded_at"` // 上传时间
	Size       int64     `json:"size"`        // 文件大小
}

// DB 本地数据存储
type DB struct {
	mu       sync.RWMutex
	path     string
	Records  []UploadRecord `json:"records"`
	LastClean time.Time     `json:"last_clean"` // 上次清理时间
}

// New 创建或加载数据库
func New(dataDir string) (*DB, error) {
	if dataDir == "" {
		home, _ := os.UserHomeDir()
		dataDir = filepath.Join(home, ".config", "vpaste")
	}

	if err := os.MkdirAll(dataDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create data dir: %w", err)
	}

	db := &DB{
		path: filepath.Join(dataDir, "records.json"),
	}

	if err := db.load(); err != nil {
		// 如果文件不存在，创建新的
		if os.IsNotExist(err) {
			db.Records = []UploadRecord{}
			db.LastClean = time.Time{}
			return db, nil
		}
		return nil, err
	}

	return db, nil
}

// AddRecord 添加上传记录
func (d *DB) AddRecord(key, cdnURL string, size int64) error {
	d.mu.Lock()
	defer d.mu.Unlock()

	record := UploadRecord{
		Key:        key,
		CDNURL:     cdnURL,
		UploadedAt: time.Now(),
		Size:       size,
	}

	d.Records = append(d.Records, record)

	// 限制记录数量，避免文件过大（保留最近1000条）
	if len(d.Records) > 1000 {
		d.Records = d.Records[len(d.Records)-1000:]
	}

	return d.save()
}

// GetRecordsToClean 获取需要清理的记录（超过保留时间的）
func (d *DB) GetRecordsToClean(retentionHours int) []UploadRecord {
	d.mu.RLock()
	defer d.mu.RUnlock()

	cutoff := time.Now().Add(-time.Duration(retentionHours) * time.Hour)
	var toClean []UploadRecord

	for _, r := range d.Records {
		if r.UploadedAt.Before(cutoff) {
			toClean = append(toClean, r)
		}
	}

	return toClean
}

// RemoveRecords 从记录中删除指定的keys（清理成功后调用）
func (d *DB) RemoveRecords(keys []string) error {
	d.mu.Lock()
	defer d.mu.Unlock()

	keySet := make(map[string]bool)
	for _, k := range keys {
		keySet[k] = true
	}

	var newRecords []UploadRecord
	for _, r := range d.Records {
		if !keySet[r.Key] {
			newRecords = append(newRecords, r)
		}
	}

	d.Records = newRecords
	d.LastClean = time.Now()

	return d.save()
}

// ShouldClean 检查是否需要清理（距离上次清理超过1小时）
func (d *DB) ShouldClean() bool {
	d.mu.RLock()
	defer d.mu.RUnlock()

	// 如果从未清理过，或者上次清理超过1小时
	return d.LastClean.IsZero() || time.Since(d.LastClean) > time.Hour
}

// MarkCleaned 标记清理完成
func (d *DB) MarkCleaned() error {
	d.mu.Lock()
	defer d.mu.Unlock()

	d.LastClean = time.Now()
	return d.save()
}

func (d *DB) load() error {
	data, err := os.ReadFile(d.path)
	if err != nil {
		return err
	}

	return json.Unmarshal(data, d)
}

func (d *DB) save() error {
	tmpPath := d.path + ".tmp"

	data, err := json.MarshalIndent(d, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal db: %w", err)
	}

	// 先写入临时文件，再原子重命名，避免数据损坏
	if err := os.WriteFile(tmpPath, data, 0644); err != nil {
		return fmt.Errorf("failed to write db: %w", err)
	}

	return os.Rename(tmpPath, d.path)
}

// Stats 返回统计信息
func (d *DB) Stats() (totalCount int, oldestTime time.Time, lastClean time.Time) {
	d.mu.RLock()
	defer d.mu.RUnlock()

	if len(d.Records) == 0 {
		return 0, time.Time{}, d.LastClean
	}

	oldest := d.Records[0].UploadedAt
	for _, r := range d.Records {
		if r.UploadedAt.Before(oldest) {
			oldest = r.UploadedAt
		}
	}

	return len(d.Records), oldest, d.LastClean
}

// GetLastClean 返回上次清理时间
func (d *DB) GetLastClean() time.Time {
	d.mu.RLock()
	defer d.mu.RUnlock()
	return d.LastClean
}
