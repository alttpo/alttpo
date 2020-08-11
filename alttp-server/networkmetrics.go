package main

import (
	influxdb2 "github.com/influxdata/influxdb-client-go"
	influxApi "github.com/influxdata/influxdb-client-go/api"
	"time"
)

type NetworkMetrics interface {
	ReceivedBytes(n int, group string, client string, kind string)
	SentBytes(n int, group string, client string, kind string)
}

type nullNetworkMetrics struct{}

func (m nullNetworkMetrics) ReceivedBytes(n int, group string, client string, kind string) {}
func (m nullNetworkMetrics) SentBytes(n int, group string, client string, kind string)     {}

type influxNetworkMetrics struct {
	w influxApi.WriteAPI
}

func (m influxNetworkMetrics) ReceivedBytes(n int, group string, client string, kind string) {
	m.w.WritePoint(influxdb2.NewPointWithMeasurement("net").
		SetTime(time.Now()).
		AddTag("group", group).
		AddTag("client", client).
		AddTag("kind", kind).
		AddField("received", n))
}

func (m influxNetworkMetrics) SentBytes(n int, group string, client string, kind string) {
	m.w.WritePoint(influxdb2.NewPointWithMeasurement("net").
		SetTime(time.Now()).
		AddTag("group", group).
		AddTag("client", client).
		AddTag("kind", kind).
		AddField("sent", n))
}
