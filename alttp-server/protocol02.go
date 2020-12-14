package main

import (
	"bytes"
	"encoding/binary"
	"log"
	"time"
)

type P02Kind byte

const (
	RequestIndex      = P02Kind(0x00)
	Broadcast         = P02Kind(0x01)
	BroadcastToSector = P02Kind(0x02)

	ReliableBroadcast = P02Kind(0x04)
	ReliableACK       = P02Kind(0x05)
)

func (k P02Kind) String() string {
	switch k {
	case RequestIndex:
		return "request_index"
	case Broadcast:
		return "broadcast"
	case BroadcastToSector:
		return "broadcast_to_sector"
	}
	return "unknown"
}

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

	// trim whitespace and convert to lowercase for key lookup:
	groupKey := calcGroupKey(group)
	clientGroup := findGroupOrCreate(groupKey)

	// create a key that represents the client from the received address:
	addr := message.ReceivedFrom
	clientKey := ClientKey{
		Port: addr.Port,
		Zone: addr.Zone,
	}
	copy(clientKey.IP[:], addr.IP)

	client, ci := findClientOrCreate(clientGroup, clientKey, addr, group, groupKey)

	// record number of bytes received:
	networkMetrics.ReceivedBytes(len(message.Envelope), kind.String(), clientGroup, client)

	switch kind {
	case RequestIndex:
		// client requests its own client index, no need to broadcast to other clients:

		// construct message:
		rsp := make02Packet(groupBuf, kind)

		// emit client index:
		index := uint16(ci)
		binary.Write(rsp, binary.LittleEndian, &index)

		// send message back to client:
		rspBytes := rsp.Bytes()
		_, fatalErr = conn.WriteToUDP(rspBytes, &client.UDPAddr)
		if fatalErr != nil {
			return
		}
		networkMetrics.SentBytes(len(rspBytes), kind.String(), clientGroup, client)
		rsp = nil

		break
	case Broadcast:
		// broadcast message received to all other clients:
		payload := buf.Bytes()
		for i := range clientGroup.Clients {
			c := &clientGroup.Clients[i]
			if !c.IsAlive {
				continue
			}
			if c == client {
				continue
			}

			responseKind := kind

			// construct message:
			rsp := make02Packet(groupBuf, responseKind)
			index := uint16(ci)
			binary.Write(rsp, binary.LittleEndian, &index)
			// write the payload:
			rsp.Write(payload)

			// send message to this client:
			rspBytes := rsp.Bytes()
			_, fatalErr = conn.WriteToUDP(rspBytes, &c.UDPAddr)
			if fatalErr != nil {
				return
			}
			networkMetrics.SentBytes(len(rspBytes), kind.String(), clientGroup, client)
			rsp = nil
			//log.Printf("[group %s] (%v) sent message to (%v)\n", groupKey, client, other)
		}
		break
	case BroadcastToSector:
		// broadcast message received to all other clients in the same sector:
		var sector uint32
		if err := binary.Read(buf, binary.LittleEndian, &sector); err != nil {
			log.Print(err)
			return
		}

		// join this client to the sector they're broadcasting to:
		client.Sector = sector

		// broadcast message:
		payload := buf.Bytes()
		for i := range clientGroup.Clients {
			c := &clientGroup.Clients[i]
			if !c.IsAlive {
				continue
			}
			if c.Sector != sector {
				continue
			}
			if c == client {
				continue
			}

			// construct message:
			rsp := make02Packet(groupBuf, Broadcast)
			index := uint16(ci)
			binary.Write(rsp, binary.LittleEndian, &index)

			// write the payload:
			rsp.Write(payload)

			// send message to this client:
			rspBytes := rsp.Bytes()
			_, fatalErr = conn.WriteToUDP(rspBytes, &c.UDPAddr)
			if fatalErr != nil {
				return
			}
			networkMetrics.SentBytes(len(rspBytes), kind.String(), clientGroup, client)
			rsp = nil
			//log.Printf("[group %s] (%v) sent message to (%v)\n", groupKey, client, other)
		}
		break
	case ReliableBroadcast:
		// received a reliable broadcast request from a client:
		var seq uint16
		if err := binary.Read(buf, binary.LittleEndian, &seq); err != nil {
			log.Print(err)
			return
		}

		// send the ACK:
		{
			rsp := make02Packet(groupBuf, ReliableACK)
			index := uint16(ci)
			binary.Write(rsp, binary.LittleEndian, &index)
			// seq:
			binary.Write(rsp, binary.LittleEndian, &seq)

			rspBytes := rsp.Bytes()
			_, fatalErr = conn.WriteToUDP(rspBytes, &client.UDPAddr)
			if fatalErr != nil {
				return
			}

			networkMetrics.SentBytes(len(rspBytes), kind.String(), clientGroup, client)
			rsp = nil
			rspBytes = nil
		}

		// broadcast it reliably to all other clients:
		payload := buf.Bytes()
		for i := range clientGroup.Clients {
			c := &clientGroup.Clients[i]
			if !c.IsAlive {
				continue
			}
			if c == client {
				continue
			}

			seq := c.sent.seq
			c.sent.seq++

			// construct message:
			rsp := make02Packet(groupBuf, ReliableBroadcast)
			index := uint16(ci)
			binary.Write(rsp, binary.LittleEndian, &index)
			binary.Write(rsp, binary.LittleEndian, &seq)

			// write the payload:
			rsp.Write(payload)

			// record the message for later retransmit:
			rspBytes := rsp.Bytes()
			sp := NewSentPacket(index, rspBytes, clientGroup, client)
			sp.RetryFunc = func() {
				// deliver message:
				if _, err := conn.WriteToUDP(sp.Payload, &sp.Client.UDPAddr); err != nil {
					return
				}
				networkMetrics.SentBytes(len(sp.Payload), ReliableBroadcast.String(), sp.ClientGroup, sp.Client)
				sp.Retry = time.AfterFunc(time.Millisecond*17, sp.RetryFunc)
			}
			sp.Retry = time.AfterFunc(time.Millisecond*33, sp.RetryFunc)
			c.sent.pkts = append(c.sent.pkts, sp)

			// send message to this client:
			if _, fatalErr = conn.WriteToUDP(rspBytes, &c.UDPAddr); fatalErr != nil {
				return
			}
			networkMetrics.SentBytes(len(rspBytes), ReliableBroadcast.String(), clientGroup, client)

			// record the sent packet:
			rsp = nil
			rspBytes = nil
			//log.Printf("[group %s] (%v) sent message to (%v)\n", groupKey, client, other)
		}
		break
	case ReliableACK:
		var seq uint16
		if err := binary.Read(buf, binary.LittleEndian, &seq); err != nil {
			log.Print(err)
			return
		}

		// find the packet:
		f := -1
		for i, p := range client.sent.pkts {
			if p.Seq != seq {
				continue
			}
			f = i
			break
		}

		// ack and remove the packet:
		if f != -1 {
			pa := client.sent.pkts
			pa[f].Ack()
			if len(pa) > 1 {
				pa[f] = pa[len(pa)-1]
				pa = pa[:len(pa)-1]
			}
			client.sent.pkts = pa
		}
		break
	}

	return
}
