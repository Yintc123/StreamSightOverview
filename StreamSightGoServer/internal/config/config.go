package config

import (
	"fmt"
	"os"
	"strconv"
	"time"
)

// Config holds all runtime configuration, loaded from environment variables.
type Config struct {
	Port string

	DatabaseDSN       string
	DBMaxOpenConns    int
	DBMaxIdleConns    int
	DBConnMaxIdleTime time.Duration
	DBConnMaxLifetime time.Duration

	RedisAddr     string
	RedisPassword string
	RedisDB       int
}

// Load reads configuration from the environment, applying sensible defaults
// that match the local infra/ docker-compose (MariaDB + Redis).
func Load() Config {
	dbUser := getEnv("DB_USER", "streamsight")
	dbPass := getEnv("DB_PASSWORD", "streamsight")
	dbHost := getEnv("DB_HOST", "127.0.0.1")
	dbPort := getEnv("DB_PORT", "3306")
	dbName := getEnv("DB_NAME", "streamsight")

	// parseTime lets the driver scan DATE/DATETIME into time.Time.
	dsn := fmt.Sprintf("%s:%s@tcp(%s:%s)/%s?parseTime=true&charset=utf8mb4&loc=Local",
		dbUser, dbPass, dbHost, dbPort, dbName)

	return Config{
		Port: getEnv("PORT", "8080"),

		DatabaseDSN:       dsn,
		DBMaxOpenConns:    getEnvInt("DB_MAX_OPEN_CONNS", 25),
		DBMaxIdleConns:    getEnvInt("DB_MAX_IDLE_CONNS", 25),
		DBConnMaxIdleTime: time.Duration(getEnvInt("DB_CONN_MAX_IDLE_SEC", 300)) * time.Second,
		DBConnMaxLifetime: time.Duration(getEnvInt("DB_CONN_MAX_LIFETIME_SEC", 1800)) * time.Second,

		RedisAddr:     fmt.Sprintf("%s:%s", getEnv("REDIS_HOST", "127.0.0.1"), getEnv("REDIS_PORT", "6379")),
		RedisPassword: getEnv("REDIS_PASSWORD", ""),
		RedisDB:       getEnvInt("REDIS_DB", 0),
	}
}

func getEnv(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return fallback
}

func getEnvInt(key string, fallback int) int {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return fallback
}
