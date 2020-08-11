package main

import (
	influxdb2 "github.com/influxdata/influxdb-client-go"
	influxApi "github.com/influxdata/influxdb-client-go/api"
	"time"
)

type GroupMetrics interface {
	TotalGroups(n int)
}

type nullGroupMetrics struct{}

func (m nullGroupMetrics) TotalGroups(n int) {}

type influxGroupMetrics struct {
	w influxApi.WriteAPI
}

func (m influxGroupMetrics) TotalGroups(n int) {
	m.w.WritePoint(influxdb2.NewPointWithMeasurement("groups").
		SetTime(time.Now()).
		AddField("total", n))
}
