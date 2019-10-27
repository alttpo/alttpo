package main

import (
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

	LastSeen time.Time
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

	clients := make(map[ClientKey]*Client)

	// we only need a single receive buffer:
	b := make([]byte, 1500)

	for {
		// wait for a packet from UDP socket:
		n, addr, err := conn.ReadFromUDP(b)
		if err != nil {
			log.Fatal(err)
		}

		// grab the slice of the message:
		msg := b[:n]
		//fmt.Printf("received %v bytes\n", n)

		// TODO: create groups to connect players together and only broadcast back to each client in the group

		// create a key that represents the client from the received address:
		key := ClientKey{
			Port: addr.Port,
			Zone: addr.Zone,
		}
		copy(key.IP[:], addr.IP)

		client, ok := clients[key]
		if !ok {
			// add this client to set of clients:
			client = &Client{
				UDPAddr:  *addr,
				LastSeen: time.Now(),
			}
			clients[key] = client
			log.Printf("(%v) new client\n", client)
		} else {
			// update time last seen:
			client.LastSeen = time.Now()
		}

		// broadcast message received to all other clients:
		for otherKey, other := range clients {
			// don't echo back to client received from:
			if other == client {
				//log.Printf("(%v) skip echo\n", otherKey.IP)
				continue
			}

			// expunge expired clients:
			if other.LastSeen.Add(disconnectTimeout).Before(time.Now()) {
				log.Printf("(%v) forget client\n", other)
				delete(clients, otherKey)
				continue
			}

			// send message to this client:
			//log.Printf("(%v) sent message\n", otherKey.IP)
			_, err := conn.WriteToUDP(msg, &other.UDPAddr)
			if err != nil {
				log.Fatal(err)
			}
		}
	}
}
