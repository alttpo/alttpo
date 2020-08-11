package main

import (
	influxdb2 "github.com/influxdata/influxdb-client-go"
	influxApi "github.com/influxdata/influxdb-client-go/api"
	"time"
)

type NetworkMetrics interface {
	ReceivedBytes(n int, kind string, group *ClientGroup, client *Client)
	SentBytes(n int, kind string, group *ClientGroup, client *Client)
}

type nullNetworkMetrics struct{}

func (m nullNetworkMetrics) ReceivedBytes(n int, kind string, group *ClientGroup, client *Client) {}
func (m nullNetworkMetrics) SentBytes(n int, kind string, group *ClientGroup, client *Client)     {}

type influxNetworkMetrics struct {
	w influxApi.WriteAPI
}

func (m influxNetworkMetrics) ReceivedBytes(n int, kind string, group *ClientGroup, client *Client) {
	m.w.WritePoint(influxdb2.NewPointWithMeasurement("net").
		SetTime(time.Now()).
		AddTag("group", group.Group).
		AddTag("group_anon", group.AnonymizedName).
		AddTag("client", client.String()).
		AddTag("kind", kind).
		AddField("received", n))
}

func (m influxNetworkMetrics) SentBytes(n int, kind string, group *ClientGroup, client *Client) {
	m.w.WritePoint(influxdb2.NewPointWithMeasurement("net").
		SetTime(time.Now()).
		AddTag("group", group.Group).
		AddTag("group_anon", group.AnonymizedName).
		AddTag("client", client.String()).
		AddTag("kind", kind).
		AddField("sent", n))
}
