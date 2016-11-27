To run:
```bash
docker run -p 8080:8080 \
           -p 8086:8086 \
           -p 2003:2003 \
           -p 4242:4242 \
           -p 9999:9999 \
           -p 1234:1234 \
           -t -i project-fifo/ddb-aio:0.3.0-dev /bin/bash
```

Currently supported ingres formats:

 * 8080 HTTP / dalmatiner frontend
 * 8087 HTTP / influxdb ingres
 * 2003 TCP / graphite
 * 4242 TCP / OTSDB
 * 9999 UDP / (bsd) syslog
 * 1234 HTTP / Prometheus remote writer protocl