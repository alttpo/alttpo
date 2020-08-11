package main

import (
	"bytes"
	"encoding/binary"
	"log"
	"strings"
	"time"
)

type P02Kind byte

const (
	RequestIndex = P02Kind(0x00)
	Broadcast    = P02Kind(0x01)
)

func make02Packet(groupBuf []byte, kind P02Kind) (buf *bytes.Buffer) {
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

	return
}

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

	// what the client thinks its index is:
	var index uint16
	if err := binary.Read(buf, binary.LittleEndian, &index); err != nil {
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

	switch kind {
	case RequestIndex:
		// client requests its own client index, no need to broadcast to other clients:

		// construct message:
		buf = make02Packet(groupBuf, kind)

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

			responseKind := kind
			if c == client {
				// inform the client about its index as a response:
				responseKind = RequestIndex
			}

			// construct message:
			buf = make02Packet(groupBuf, responseKind)
			index := uint16(ci)
			binary.Write(buf, binary.LittleEndian, &index)

			if c != client {
				// write the payload to other clients:
				buf.Write(payload)
			}

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
