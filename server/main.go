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

func main() {
	flag.Parse()

	udpAddr, err := net.ResolveUDPAddr(network, *listen)
	if err != nil {
		log.Fatal(err)
	}

	conn, err := net.ListenUDP(network, udpAddr)
	if err != nil {
		log.Fatal(err)
	}
	defer conn.Close()

	clientGroups := make(map[string]ClientGroup)

	// we only need a single receive buffer:
	b := make([]byte, 1500)

	for {
		// wait for a packet from UDP socket:
		n, addr, err := conn.ReadFromUDP(b)
		if err != nil {
			log.Fatal(err)
		}

		// grab the slice of the envelope:
		envelope := b[:n]
		//fmt.Printf("received %v bytes\n", n)

		if len(envelope) < 3 {
			continue
		}

		buf := bytes.NewBuffer(envelope)

		var header uint16
		if binary.Read(buf, binary.LittleEndian, &header) != nil {
			continue
		}

		// 0x651F = 25887 = "ALTTP" on dialpad (T9)
		if header != 25887 {
			continue
		}

		var name string
		var group string
		name, err = readTinyString(buf)
		if err != nil {
			continue
		}
		group, err = readTinyString(buf)
		if err != nil {
			continue
		}

		// read the size of the remaining payload:
		var payloadSize uint16
		if binary.Read(buf, binary.LittleEndian, &payloadSize) != nil {
			continue
		}

		if buf.Len() < int(payloadSize) {
			continue
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
		for otherKey, other := range clientGroup {
			// don't echo back to client received from:
			if other == client {
				//log.Printf("(%v) skip echo\n", otherKey.IP)
				continue
			}

			// expunge expired clients:
			if other.LastSeen.Add(disconnectTimeout).Before(time.Now()) {
				log.Printf("(%v) forget client\n", other)
				delete(clientGroup, otherKey)
				continue
			}

			// send message to this client:
			//log.Printf("(%v) sent message\n", otherKey.IP)
			_, err := conn.WriteToUDP(msg, &other.UDPAddr)
			if err != nil {
				log.Fatal(err)
			}
		}

		// remove the client group if no more clients left:
		if len(clientGroup) == 0 {
			delete(clientGroups, group)
		}
	}
}
