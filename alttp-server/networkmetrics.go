package main

import (
	influxdb2 "github.com/influxdata/influxdb-client-go"
	influxApi "github.com/influxdata/influxdb-client-go/api"
	"time"
)

type NetworkMetrics interface {
	ReceivedBytes(n int)
	WrittenBytes(n int)
}

type nullNetworkMetrics struct{}

func (m nullNetworkMetrics) ReceivedBytes(n int) {}
func (m nullNetworkMetrics) WrittenBytes(n int)  {}

type influxNetworkMetrics struct {
	w influxApi.WriteAPI
}

func (m influxNetworkMetrics) ReceivedBytes(n int) {
	m.w.WritePoint(influxdb2.NewPointWithMeasurement("net_received").
		SetTime(time.Now()).
		AddField("bytes", n))
}

func (m influxNetworkMetrics) WrittenBytes(n int) {
	m.w.WritePoint(influxdb2.NewPointWithMeasurement("net_written").
		SetTime(time.Now()).
		AddField("bytes", n))
}
