package main

import (
	"bytes"
	"encoding/binary"
	"flag"
	"log"
	"net"
	"runtime"
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

	IsAlive   bool
	Group     string
	ClientKey ClientKey
	Index     uint16
	Sector    uint32

	LastSeen time.Time
}

//type ClientGroup map[ClientKey]*Client
type ClientGroup struct {
	Group string

	Clients     []Client
	ActiveCount int
}

var udpAddr *net.UDPAddr
var conn *net.UDPConn
var clientGroups map[string]*ClientGroup

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

		// copy the envelope:
		envelope := make([]byte, n)
		copy(envelope, b[:n])

		messages <- UDPMessage{
			Envelope:     envelope,
			ReceivedFrom: addr,
		}
	}
}

func main() {
	flag.Parse()

	var err error

	udpAddr, err = net.ResolveUDPAddr(network, *listen)
	if err != nil {
		log.Fatal(err)
	}

	log.Printf("getting ready to listen on %s %s; pass the -listen flag to change", network, udpAddr)
	conn, err = net.ListenUDP(network, udpAddr)
	if err != nil {
		log.Fatal(err)
	}
	defer conn.Close()

	log.Printf("listening on %s %s", network, udpAddr)
	udpMessages := make(chan UDPMessage)
	for i := 0; i < runtime.NumCPU(); i++ {
		go getPackets(conn, udpMessages)
	}

	clientGroups = make(map[string]*ClientGroup)

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
	//log.Printf("(%v) received %v bytes\n", addr, len(envelope))

	buf := bytes.NewBuffer(message.Envelope)

	var header uint16
	if err := binary.Read(buf, binary.LittleEndian, &header); err != nil {
		log.Print(err)
		return
	}

	// 0x651F = 25887 = "ALTTP" on dialpad (T9)
	if header != 25887 {
		log.Printf("bad header %04x\n", header)
		return
	}

	var protocol uint8
	if err := binary.Read(buf, binary.LittleEndian, &protocol); err != nil {
		log.Print(err)
		return
	}

	switch protocol {
	case 0x01:
		return processProtocol01(message, buf)
	case 0x02:
		return processProtocol02(message, buf)
	default:
		log.Printf("unknown protocol 0x%02x\n", protocol)
	}

	return
}

func expireClients(seconds time.Time) {
	// find all client groups with clients to expire in them:
	for groupKey, clientGroup := range clientGroups {
		// find all clients to be expired:
		for i := range clientGroup.Clients {
			c := &clientGroup.Clients[i]
			if !c.IsAlive {
				continue
			}

			// expunge expired clients:
			if c.LastSeen.Add(disconnectTimeout).Before(seconds) {
				c.IsAlive = false
				clientGroup.ActiveCount--
				log.Printf("[group %s] (%v) forget client, clients=%d\n", groupKey, c, clientGroup.ActiveCount)
			}
		}

		// remove the client group if no more clients left within:
		if clientGroup.ActiveCount == 0 {
			delete(clientGroups, groupKey)
			log.Printf("[group %s] forget group\n", groupKey)
		}
	}
}
