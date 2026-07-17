package health

import (
	"context"
	"database/sql"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
)

type checker struct {
	db  *sql.DB
	rdb *redis.Client
}

// Register wires the health endpoints onto the router.
//
//	GET /healthz  liveness  — is this process up? (no external deps)
//	GET /readyz   readiness — is the server + db + redis all reachable?
func Register(r *gin.Engine, db *sql.DB, rdb *redis.Client) {
	c := &checker{db: db, rdb: rdb}
	r.GET("/healthz", c.liveness)
	r.GET("/readyz", c.readiness)
}

// liveness always reports ok while the process can serve requests. Point the
// ECS/ALB liveness probe here so a slow DB doesn't trigger a restart loop.
func (c *checker) liveness(ctx *gin.Context) {
	ctx.JSON(http.StatusOK, gin.H{"status": "ok"})
}

// readiness pings every dependency and returns 503 if any is down, so the load
// balancer stops routing traffic to a task that can't actually serve.
func (c *checker) readiness(ctx *gin.Context) {
	reqCtx, cancel := context.WithTimeout(ctx.Request.Context(), 2*time.Second)
	defer cancel()

	checks := gin.H{"server": "ok", "db": "ok", "redis": "ok"}
	healthy := true

	if err := c.db.PingContext(reqCtx); err != nil {
		checks["db"] = "error: " + err.Error()
		healthy = false
	}
	if err := c.rdb.Ping(reqCtx).Err(); err != nil {
		checks["redis"] = "error: " + err.Error()
		healthy = false
	}

	status := http.StatusOK
	overall := "ok"
	if !healthy {
		status = http.StatusServiceUnavailable
		overall = "degraded"
	}
	ctx.JSON(status, gin.H{"status": overall, "checks": checks})
}
