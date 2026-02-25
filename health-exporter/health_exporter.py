#!/usr/bin/env python3
"""
Health Check Exporter for Kessel Services

This exporter calls health endpoints of services that don't expose
Prometheus metrics and converts them to Prometheus format.

NOTE: In kessel-in-a-box (minimal demo), no services are monitored
by this exporter. This exporter is included for future use or when
deploying the full Kessel stack with inventory-api, relations-api, etc.

Services that COULD be monitored (in full deployment):
- kessel-inventory-api
- kessel-relations-api
- insights-rbac
- insights-host-inventory
"""

import time
import requests
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Service health check configurations
# Internal container ports (not host-mapped ports):
#   kessel-relations-api: HTTP 8000 (POST /api/authz/v1beta1/tuples), gRPC 9000
#   kessel-inventory-api: HTTP 8000 (/api/kessel/v1/livez), gRPC 9000
#   insights-rbac:        HTTP 8080 (/api/rbac/v1/status/)
#   insights-host-inventory: HTTP 8080 (/health) — returns 200 with empty body
SERVICES = {
    'relations-api': {
        'url': 'http://kessel-relations-api:8000/api/authz/v1beta1/tuples',
        'timeout': 5,
        'method': 'POST',
        'body': '{"tuples":[]}',
    },
    'inventory-api': {
        'url': 'http://kessel-inventory-api:8000/api/kessel/v1/livez',
        'timeout': 5,
    },
    'rbac': {
        'url': 'http://insights-rbac:8080/api/rbac/v1/status/',
        'timeout': 5,
    },
    'host-inventory': {
        'url': 'http://insights-host-inventory:8080/health',
        'timeout': 5,
    },
}

def check_service_health(service_name, config):
    """
    Check health of a service by calling its health endpoint.

    Returns:
        1 if healthy, 0 if unhealthy
    """
    try:
        method = config.get('method', 'GET').upper()
        if method == 'POST':
            response = requests.post(
                config['url'],
                data=config.get('body', ''),
                headers={'Content-Type': 'application/json'},
                timeout=config['timeout'],
                allow_redirects=True
            )
        else:
            response = requests.get(
                config['url'],
                timeout=config['timeout'],
                allow_redirects=True
            )

        # Consider 2xx and 3xx as healthy
        if 200 <= response.status_code < 400:
            logger.debug(f"{service_name}: UP (status {response.status_code})")
            return 1
        else:
            logger.warning(f"{service_name}: DOWN (status {response.status_code})")
            return 0

    except requests.exceptions.Timeout:
        logger.warning(f"{service_name}: TIMEOUT")
        return 0
    except requests.exceptions.ConnectionError:
        logger.warning(f"{service_name}: CONNECTION_ERROR")
        return 0
    except Exception as e:
        logger.error(f"{service_name}: ERROR - {str(e)}")
        return 0

def generate_metrics():
    """
    Generate Prometheus metrics by checking all service health endpoints.

    Returns:
        Prometheus-formatted metrics as string
    """
    metrics = []

    # Add metric header
    metrics.append("# HELP up Health check status (1 = up, 0 = down)")
    metrics.append("# TYPE up gauge")

    # Check each service
    for service_name, config in SERVICES.items():
        status = check_service_health(service_name, config)

        # Generate metric with labels
        metrics.append(f'up{{job="{service_name}"}} {status}')

    # Add a timestamp
    metrics.append(f"# Health checks completed at {int(time.time())}")

    return "\n".join(metrics) + "\n"

class HealthExporterHandler(BaseHTTPRequestHandler):
    """HTTP handler for Prometheus metrics endpoint."""

    def do_GET(self):
        """Handle GET requests."""

        if self.path == '/metrics':
            # Generate and return metrics
            try:
                metrics = generate_metrics()

                self.send_response(200)
                self.send_header('Content-Type', 'text/plain; version=0.0.4')
                self.end_headers()
                self.wfile.write(metrics.encode('utf-8'))

            except Exception as e:
                logger.error(f"Error generating metrics: {e}")
                self.send_error(500, f"Internal Server Error: {str(e)}")

        elif self.path == '/health' or self.path == '/healthz':
            # Exporter's own health check
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b"OK\n")

        else:
            self.send_error(404, "Not Found")

    def log_message(self, format, *args):
        """Override to use proper logging."""
        logger.info(format % args)

def run_server(port=9091):
    """Run the HTTP server."""
    server_address = ('', port)
    httpd = HTTPServer(server_address, HealthExporterHandler)

    logger.info(f"Health Check Exporter starting on port {port}")
    logger.info(f"Monitoring services: {', '.join(SERVICES.keys())}")
    logger.info(f"Metrics endpoint: http://0.0.0.0:{port}/metrics")

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        logger.info("Shutting down...")
        httpd.shutdown()

if __name__ == '__main__':
    run_server()
