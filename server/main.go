package main

import (
	"bytes"
	"encoding/binary"
	"flag"
	"log"
	"net"
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

	Name     string
	Group    string
	LastSeen time.Time
}

type ClientGroup map[ClientKey]*Client

func readTinyString(buf *bytes.Buffer) (value string, err error) {
	var valueLength uint8
	if err = binary.Read(buf, binary.LittleEndian, &valueLength); err != nil {
		return
	}

	valueBytes := make([]byte, 0, valueLength)
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

	for {
		select {
		case udpMessage, more := <-udpMessages:
			// exit loop if udpMessages channel is closed:
			if !more {
				break
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
}

func processMessage(message UDPMessage) (fatalErr error) {
	envelope := message.Envelope
	addr := message.ReceivedFrom

	//fmt.Printf("received %v bytes\n", n)

	if len(envelope) < 3 {
		return
	}

	buf := bytes.NewBuffer(envelope)

	var header uint16
	if binary.Read(buf, binary.LittleEndian, &header) != nil {
		return
	}

	// 0x651F = 25887 = "ALTTP" on dialpad (T9)
	if header != 25887 {
		return
	}

	var name string
	var group string
	var err error
	name, err = readTinyString(buf)
	if err != nil {
		return
	}
	group, err = readTinyString(buf)
	if err != nil {
		return
	}

	// read the size of the remaining payload:
	var payloadSize uint16
	if binary.Read(buf, binary.LittleEndian, &payloadSize) != nil {
		return
	}

	if buf.Len() < int(payloadSize) {
		return
	}

	msg := buf.Bytes()[:payloadSize]
	buf = nil

	clientGroup, ok := clientGroups[group]
	if !ok {
		clientGroup = make(ClientGroup)
		clientGroups[group] = clientGroup
	}

	// create a key that represents the client from the received address:
	key := ClientKey{
		Port: addr.Port,
		Zone: addr.Zone,
	}
	copy(key.IP[:], addr.IP)

	client, ok := clientGroup[key]
	if !ok {
		// add this client to set of clients:
		client = &Client{
			UDPAddr:  *addr,
			LastSeen: time.Now(),
			Name:     name,
			Group:    group,
		}
		clientGroup[key] = client
		log.Printf("(%v) new client\n", client)
	} else {
		// update time last seen:
		client.LastSeen = time.Now()
		client.Name = name
		client.Group = group
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
		_, fatalErr = conn.WriteToUDP(msg, &other.UDPAddr)
		if fatalErr != nil {
			return
		}
	}

	return
}

func expireClients(seconds time.Time) {
	// find all client groups with clients to expire in them:
	for groupName, clientGroup := range clientGroups {
		// find all clients to be expired:
		for otherKey, other := range clientGroup {
			// expunge expired clients:
			if other.LastSeen.Add(disconnectTimeout).Before(seconds) {
				log.Printf("(%v) forget client\n", other)
				delete(clientGroup, otherKey)
			}
		}

		// remove the client group if no more clients left within:
		if len(clientGroup) == 0 {
			delete(clientGroups, groupName)
		}
	}
}
