package main

import (
	"bytes"
	"encoding/binary"
	"log"
	"strings"
	"time"
)

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
		reportGroupClients(clientGroup)
		reportTotalGroups()
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
		reportGroupClients(clientGroup)
		reportTotalClients()
	} else {
		// update time last seen:
		client.LastSeen = time.Now()
	}

	// record number of bytes received:
	networkMetrics.ReceivedBytes(len(message.Envelope), groupKey, client.String(), "broadcast")

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
		bufBytes := buf.Bytes()
		_, fatalErr = conn.WriteToUDP(bufBytes, &c.UDPAddr)
		if fatalErr != nil {
			return
		}
		networkMetrics.SentBytes(len(bufBytes), groupKey, client.String(), "broadcast")
		buf = nil
		//log.Printf("[group %s] (%v) sent message to (%v)\n", groupKey, client, other)
	}

	return
}
