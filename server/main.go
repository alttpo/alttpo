package main

import (
	"bytes"
	"encoding/binary"
	"flag"
	"log"
	"net"
	"strings"
	"time"
)

const (
	network           = "udp"
	disconnectTimeout = time.Second * 15
)

var (
	listen = flag.String("listen", ":4590", "UDP address to listen on")
)

type ClientKey struct {
	IP   [16]byte
	Port int
	Zone string // IPv6 scoped addressing zone
}

type Client struct {
	net.UDPAddr

	ClientType uint8
	Group      string
	Name       string
	LastSeen   time.Time
}

const (
	ClientTypeSpectator = uint8(iota)
	ClientTypePlayer
)

type ClientGroup map[ClientKey]*Client

func readTinyString(buf *bytes.Buffer) (value string, err error) {
	var valueLength uint8
	if err = binary.Read(buf, binary.LittleEndian, &valueLength); err != nil {
		return
	}

	valueBytes := make([]byte, valueLength)
	var n int
	n, err = buf.Read(valueBytes)
	if err != nil {
		return
	}
	if n < int(valueLength) {
		return
	}

	value = string(valueBytes)
	return
}

type UDPMessage struct {
	Envelope     []byte
	ReceivedFrom *net.UDPAddr
}

func getPackets(conn *net.UDPConn, messages chan<- UDPMessage) {
	// we only need a single receive buffer:
	b := make([]byte, 1500)

	for {
		// wait for a packet from UDP socket:
		var n, addr, err = conn.ReadFromUDP(b)
		if err != nil {
			log.Print(err)
			close(messages)
			return
		}

		// grab the slice of the envelope:
		envelope := b[:n]

		messages <- UDPMessage{
			Envelope:     envelope,
			ReceivedFrom: addr,
		}
	}
}

var udpAddr *net.UDPAddr
var conn *net.UDPConn
var clientGroups map[string]ClientGroup

func main() {
	flag.Parse()

	var err error

	udpAddr, err = net.ResolveUDPAddr(network, *listen)
	if err != nil {
		log.Fatal(err)
	}

	conn, err = net.ListenUDP(network, udpAddr)
	if err != nil {
		log.Fatal(err)
	}
	defer conn.Close()

	udpMessages := make(chan UDPMessage)
	go getPackets(conn, udpMessages)

	clientGroups = make(map[string]ClientGroup)

	secondsTicker := time.Tick(time.Second * 5)

eventloop:
	for {
		select {
		case udpMessage, more := <-udpMessages:
			// exit loop if udpMessages channel is closed:
			if !more {
				log.Print("channel closed\n")
				break eventloop
			}
			// process incoming message:
			err = processMessage(udpMessage)
			if err != nil {
				log.Fatal(err)
			}
		case seconds := <-secondsTicker:
			// expunge any expired clients every 5 seconds:
			expireClients(seconds)
		}
	}

	log.Print("main loop done\n")
}

func processMessage(message UDPMessage) (fatalErr error) {
	envelope := message.Envelope
	addr := message.ReceivedFrom

	//log.Printf("(%v) received %v bytes\n", addr, len(envelope))

	buf := bytes.NewBuffer(envelope)

	var header uint16
	if err := binary.Read(buf, binary.LittleEndian, &header); err != nil {
		log.Print(err)
		return
	}

	// 0x651F = 25887 = "ALTTP" on dialpad (T9)
	if header != 25887 {
		log.Print("bad header\n")
		return
	}

	var clientType uint8
	if err := binary.Read(buf, binary.LittleEndian, &clientType); err != nil {
		log.Print(err)
		return
	}

	var err error
	var group string
	group, err = readTinyString(buf)
	if err != nil {
		log.Print(err)
		return
	}

	var name string
	name, err = readTinyString(buf)
	if err != nil {
		log.Print(err)
		return
	}

	buf = nil

	// trim whitespace and convert to lowercase for key lookup:
	groupKey := strings.Trim(group, " \t\r\n+='\",.<>[]{}()*&^%$#@!~`?|\\;:/")
	groupKey = strings.ToLower(groupKey)
	clientGroup, ok := clientGroups[groupKey]
	if !ok {
		clientGroup = make(ClientGroup)
		clientGroups[groupKey] = clientGroup
	}

	// create a key that represents the client from the received address:
	clientKey := ClientKey{
		Port: addr.Port,
		Zone: addr.Zone,
	}
	copy(clientKey.IP[:], addr.IP)

	client, ok := clientGroup[clientKey]
	if !ok {
		// add this client to set of clients:
		client = &Client{
			UDPAddr:    *addr,
			LastSeen:   time.Now(),
			ClientType: clientType,
			Group:      group,
			Name:       name,
		}
		clientGroup[clientKey] = client
		log.Printf("[group %s] (%v) new client, clients=%d\n", groupKey, client, len(clientGroup))
	} else {
		// update time last seen:
		client.LastSeen = time.Now()
		client.ClientType = clientType
		client.Group = group
		client.Name = name
	}

	// broadcast message received to all other clients:
	for _, other := range clientGroup {
		// don't echo back to client received from:
		if other == client {
			//log.Printf("(%v) skip echo\n", otherKey.IP)
			continue
		}

		// send message to this client:
		//log.Printf("(%v) sent message\n", otherKey.IP)
		_, fatalErr = conn.WriteToUDP(envelope, &other.UDPAddr)
		if fatalErr != nil {
			return
		}
	}

	return
}

func expireClients(seconds time.Time) {
	// TODO: find a better way than linear search and iterating over all groups and all clients

	// find all client groups with clients to expire in them:
	for groupKey, clientGroup := range clientGroups {
		// find all clients to be expired:
		for otherKey, other := range clientGroup {
			// expunge expired clients:
			if other.LastSeen.Add(disconnectTimeout).Before(seconds) {
				log.Printf("[group %s] (%v) forget client, clients=%d\n", groupKey, other, len(clientGroup))
				delete(clientGroup, otherKey)
			}
		}

		// remove the client group if no more clients left within:
		if len(clientGroup) == 0 {
			log.Printf("[group %s] forget group\n", groupKey)
			delete(clientGroups, groupKey)
		}
	}
}
