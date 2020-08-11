package main

import (
	influxdb2 "github.com/influxdata/influxdb-client-go"
	influxApi "github.com/influxdata/influxdb-client-go/api"
	"time"
)

type ClientMetrics interface {
	TotalClients(n int)
}

type nullClientMetrics struct{}

func (m nullClientMetrics) TotalClients(n int) {}

type influxClientMetrics struct {
	w influxApi.WriteAPI
}

func (m influxClientMetrics) TotalClients(n int) {
	m.w.WritePoint(influxdb2.NewPointWithMeasurement("clients").
		SetTime(time.Now()).
		AddField("total", n))
}
