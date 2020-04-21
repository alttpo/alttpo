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

	IsAlive   bool
	Group     string
	ClientKey ClientKey
	Index     uint16

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
	go getPackets(conn, udpMessages)

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

func processProtocol01(message UDPMessage, buf *bytes.Buffer) (fatalErr error) {
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

	var clientType uint8
	if err := binary.Read(buf, binary.LittleEndian, &clientType); err != nil {
		log.Print(err)
		return
	}

	// TODO: emit Index back to clients
	payload := buf.Bytes()

	buf = nil

	// trim whitespace and convert to lowercase for key lookup:
	groupKey := strings.Trim(group, " \t\r\n+='\",.<>[]{}()*&^%$#@!~`?|\\;:/")
	groupKey = strings.ToLower(groupKey)
	clientGroup, ok := clientGroups[groupKey]
	if !ok {
		clientGroup = &ClientGroup{
			Group:   groupKey,
			Clients: make([]Client, 0, 8),
		}
		clientGroups[groupKey] = clientGroup
		log.Printf("[group %s] new group\n", groupKey)
	}

	// create a key that represents the client from the received address:
	addr := message.ReceivedFrom
	clientKey := ClientKey{
		Port: addr.Port,
		Zone: addr.Zone,
	}
	copy(clientKey.IP[:], addr.IP)

	// Find client in Clients array by ClientKey
	// Find first free slot to reuse
	// Find total count of active clients
	var client *Client
	ci := -1
	free := -1
	var i int
	activeCount := 0
	for i = range clientGroup.Clients {
		c := &clientGroup.Clients[i]
		if !c.IsAlive {
			if free == -1 {
				free = i
			}
			continue
		}

		activeCount++
		if c.ClientKey == clientKey {
			client = c
			ci = i
		}
	}

	// update ActiveCount:
	clientGroup.ActiveCount = activeCount

	// Add new or update existing client:
	if client == nil {
		// No free slot?
		if free == -1 {
			// Extend Clients array:
			clientGroup.Clients = append(clientGroup.Clients, Client{})
			free = len(clientGroup.Clients) - 1
		}
		ci = free
		client = &clientGroup.Clients[free]

		// add this client to set of clients:
		*client = Client{
			UDPAddr:   *addr,
			IsAlive:   true,
			Group:     group,
			ClientKey: clientKey,
			Index:     uint16(free),
			LastSeen:  time.Now(),
		}

		clientGroup.ActiveCount++
		log.Printf("[group %s] (%v) new client, clients=%d\n", groupKey, client, clientGroup.ActiveCount)
	} else {
		// update time last seen:
		client.LastSeen = time.Now()
	}

	// broadcast message received to all other clients:
	for i = range clientGroup.Clients {
		c := &clientGroup.Clients[i]
		// don't echo back to client received from:
		if c == client {
			//log.Printf("(%v) skip echo\n", otherKey.IP)
			continue
		}
		if !c.IsAlive {
			continue
		}

		// construct message:
		buf = &bytes.Buffer{}
		header := uint16(25887)
		binary.Write(buf, binary.LittleEndian, &header)
		protocol := byte(0x01)
		buf.WriteByte(protocol)

		// protocol packet:
		buf.WriteByte(uint8(len(group)))
		buf.WriteString(group)
		buf.WriteByte(uint8(len(name)))
		buf.WriteString(name)
		index := uint16(ci)
		binary.Write(buf, binary.LittleEndian, &index)
		buf.WriteByte(clientType)
		buf.Write(payload)

		// send message to this client:
		_, fatalErr = conn.WriteToUDP(buf.Bytes(), &c.UDPAddr)
		if fatalErr != nil {
			return
		}
		buf = nil
		//log.Printf("[group %s] (%v) sent message to (%v)\n", groupKey, client, other)
	}

	return
}

type P02Kind byte

const (
	RequestIndex = P02Kind(0x00)
	Broadcast    = P02Kind(0x01)
)

func processProtocol02(message UDPMessage, buf *bytes.Buffer) (fatalErr error) {
	groupBuf := make([]byte, 20)
	_, err := buf.Read(groupBuf)
	if err != nil {
		log.Print(err)
		return
	}
	group := string(groupBuf[:])
	if len(group) != 20 {
		log.Fatal("bug! group name must be exactly 20 bytes")
		return
	}

	var kind P02Kind
	if err := binary.Read(buf, binary.LittleEndian, &kind); err != nil {
		log.Print(err)
		return
	}

	payload := buf.Bytes()

	buf = nil

	// trim whitespace and convert to lowercase for key lookup:
	groupKey := strings.Trim(group, " \t\r\n+='\",.<>[]{}()*&^%$#@!~`?|\\;:/")
	groupKey = strings.ToLower(groupKey)
	clientGroup, ok := clientGroups[groupKey]
	if !ok {
		clientGroup = &ClientGroup{
			Group:   groupKey,
			Clients: make([]Client, 0, 8),
		}
		clientGroups[groupKey] = clientGroup
		log.Printf("p02 [group %s] new group\n", groupKey)
	}

	// create a key that represents the client from the received address:
	addr := message.ReceivedFrom
	clientKey := ClientKey{
		Port: addr.Port,
		Zone: addr.Zone,
	}
	copy(clientKey.IP[:], addr.IP)

	// Find client in Clients array by ClientKey
	// Find first free slot to reuse
	// Find total count of active clients
	var client *Client
	ci := -1
	free := -1
	var i int
	activeCount := 0
	for i = range clientGroup.Clients {
		c := &clientGroup.Clients[i]
		if !c.IsAlive {
			if free == -1 {
				free = i
			}
			continue
		}

		activeCount++
		if c.ClientKey == clientKey {
			client = c
			ci = i
		}
	}

	// update ActiveCount:
	clientGroup.ActiveCount = activeCount

	// Add new or update existing client:
	if client == nil {
		// No free slot?
		if free == -1 {
			// Extend Clients array:
			clientGroup.Clients = append(clientGroup.Clients, Client{})
			free = len(clientGroup.Clients) - 1
		}
		ci = free
		client = &clientGroup.Clients[free]

		// add this client to set of clients:
		*client = Client{
			UDPAddr:   *addr,
			IsAlive:   true,
			Group:     group,
			ClientKey: clientKey,
			Index:     uint16(free),
			LastSeen:  time.Now(),
		}

		clientGroup.ActiveCount++
		log.Printf("p02 [group %s] (%v) new client, clients=%d\n", groupKey, client, clientGroup.ActiveCount)
	} else {
		// update time last seen:
		client.LastSeen = time.Now()
	}

	switch kind {
	case RequestIndex:
		// client requests its own client index, no need to broadcast to other clients:

		// construct message:
		buf = &bytes.Buffer{}
		header := uint16(25887)
		binary.Write(buf, binary.LittleEndian, &header)
		protocol := byte(0x02)
		buf.WriteByte(protocol)

		// protocol packet:
		buf.Write(groupBuf)
		responseKind := kind | 0x80
		buf.WriteByte(byte(responseKind))

		// emit client index:
		index := uint16(ci)
		binary.Write(buf, binary.LittleEndian, &index)

		// send message back to client:
		_, fatalErr = conn.WriteToUDP(buf.Bytes(), &client.UDPAddr)
		if fatalErr != nil {
			return
		}
		buf = nil

		break
	case Broadcast:
		// broadcast message received to all other clients:
		for i = range clientGroup.Clients {
			c := &clientGroup.Clients[i]
			if !c.IsAlive {
				continue
			}
			// don't echo back to client received from:
			if c == client {
				continue
			}

			// construct message:
			buf = &bytes.Buffer{}
			header := uint16(25887)
			binary.Write(buf, binary.LittleEndian, &header)
			protocol := byte(0x02)
			buf.WriteByte(protocol)

			// protocol packet:
			buf.Write(groupBuf)
			responseKind := kind | 0x80
			buf.WriteByte(byte(responseKind))
			index := uint16(ci)
			binary.Write(buf, binary.LittleEndian, &index)

			// write the payload:
			buf.Write(payload)

			// send message to this client:
			_, fatalErr = conn.WriteToUDP(buf.Bytes(), &c.UDPAddr)
			if fatalErr != nil {
				return
			}
			buf = nil
			//log.Printf("[group %s] (%v) sent message to (%v)\n", groupKey, client, other)
		}
		break
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
