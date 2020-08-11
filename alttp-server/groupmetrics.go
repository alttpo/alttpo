package main

import (
	influxdb2 "github.com/influxdata/influxdb-client-go"
	influxApi "github.com/influxdata/influxdb-client-go/api"
	"time"
)

type GroupMetrics interface {
	TotalGroups(n int)
	GroupClients(group *ClientGroup, clientCount int)
}

type nullGroupMetrics struct{}

func (m nullGroupMetrics) TotalGroups(n int)                    {}
func (m nullGroupMetrics) GroupClients(group *ClientGroup, count int) {}

type influxGroupMetrics struct {
	w influxApi.WriteAPI
}

func (m influxGroupMetrics) TotalGroups(n int) {
	m.w.WritePoint(influxdb2.NewPointWithMeasurement("groups").
		SetTime(time.Now()).
		AddField("count", n))
}

func (m influxGroupMetrics) GroupClients(group *ClientGroup, clientCount int) {
	m.w.WritePoint(influxdb2.NewPointWithMeasurement("groups").
		SetTime(time.Now()).
		AddTag("group", group.Group).
		AddTag("group_anon", group.AnonymizedName).
		AddField("clients", clientCount))
}
