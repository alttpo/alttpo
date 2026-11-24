// Facts (see o2-server's PROTOCOL05.md, "Facts"), the same as o2's facts.go.
//
// A fact is immutable data a player uploads once; the server keeps it and hands it to the others. alttpo uploads its
// facts (build_local_facts) after every new join: the first chunk alone, then, unless the server answers that it has
// the fact already, the rest at facts_put_per_tick chunks per tick, resending what fact-status doesn't mark received
// after facts_resend_ms. The server's fact-lists say which facts each player has (number, size and hash); fact
// contents are kept by hash, our own included, and a remote player's fact is downloaded only when something asks for
// it (fact_data). The server computes the hashes; alttpo doesn't hash anything.

const int facts_put_per_tick = 4;
const uint64 facts_resend_ms = 250;
const int facts_get_in_flight = 16;

class LocalFact {
  uint8 num;
  array<uint8> data;
  uint64 received = 0;
  bool status = false;
  bool complete = false;
  bool rejected = false;
  array<uint64> sent_ms;

  LocalFact() { sent_ms.resize(64); }

  void restart() {
    received = 0;
    status = false;
    complete = false;
    rejected = false;
    for (uint i = 0; i < 64; i++) sent_ms[i] = 0;
  }
}

class FactEntry {
  uint16 index;
  uint8 num;
  uint size;
  array<uint8> hash;
}

class StoredFact {
  array<uint8> hash;
  array<uint8> data;
}

class FactDownload {
  uint16 index;
  uint8 num;
  uint size;
  array<uint8> hash;
  array<uint8> data;
  uint64 have = 0;
  array<uint64> asked_ms;

  FactDownload() { asked_ms.resize(64); }
}

array<LocalFact@> local_facts;
bool local_facts_built = false;
array<FactEntry@> fact_lists;
array<StoredFact@> fact_store;
array<FactDownload@> fact_downloads;

uint fact_chunk_count(uint size) {
  return (size + p5_fact_chunk_size - 1) / p5_fact_chunk_size;
}

uint64 fact_all_chunks(uint size) {
  uint n = fact_chunk_count(size);
  if (n >= 64) return 0xFFFFFFFFFFFFFFFF;
  return (uint64(1) << n) - 1;
}

uint fact_chunk_len(uint size, uint i) {
  uint n = size - i * p5_fact_chunk_size;
  if (n > p5_fact_chunk_size) n = p5_fact_chunk_size;
  return n;
}

bool hash_equal(const array<uint8> &in a, const array<uint8> &in b) {
  if (a.length() != b.length()) return false;
  for (uint i = 0; i < a.length(); i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

StoredFact@ fact_stored(const array<uint8> &in hash) {
  for (uint i = 0; i < fact_store.length(); i++) {
    if (hash_equal(fact_store[i].hash, hash)) return fact_store[i];
  }
  return null;
}

void fact_store_put(const array<uint8> &in hash, const array<uint8> &in data) {
  if (fact_stored(hash) !is null) return;
  StoredFact s;
  s.hash = hash;
  s.data = data;
  fact_store.insertLast(s);
}

FactEntry@ fact_listed(uint16 index, uint8 num) {
  for (uint i = 0; i < fact_lists.length(); i++) {
    if (fact_lists[i].index == index && fact_lists[i].num == num) return fact_lists[i];
  }
  return null;
}

LocalFact@ local_fact(uint8 num) {
  for (uint i = 0; i < local_facts.length(); i++) {
    if (local_facts[i].num == num) return local_facts[i];
  }
  return null;
}

// facts_joined starts the uploads again after a new join: the server may have lost our facts.
void facts_joined() {
  for (uint i = 0; i < local_facts.length(); i++) {
    local_facts[i].restart();
  }
}

// facts_tick sends the chunks of our facts the server lacks and asks for the chunks of the downloads in progress.
void facts_tick() {
  if (local.index < 0 || !p5.join_acked) return;
  if (!local_facts_built) {
    local_facts_built = true;
    build_local_facts();
  }
  uint64 now = chrono::monotonic::millisecond;

  int budget = facts_put_per_tick;
  for (uint f = 0; f < local_facts.length() && budget > 0; f++) {
    auto @lf = local_facts[f];
    if (lf.complete || lf.rejected) continue;
    uint size = lf.data.length();
    uint count = fact_chunk_count(size);
    for (uint i = 0; i < count && budget > 0; i++) {
      if ((lf.received & (uint64(1) << i)) != 0) continue;
      if (lf.sent_ms[i] != 0 && now - lf.sent_ms[i] < facts_resend_ms) continue;
      // the first chunk alone until the server says whether it has the fact:
      if (i > 0 && !lf.status) break;
      lf.sent_ms[i] = now;
      auto @pkt = p5_packet(p5_fact_put);
      pkt.write_u8(lf.num);
      pkt.write_u32(size);
      pkt.write_u8(uint8(i));
      uint o = i * p5_fact_chunk_size;
      uint n = fact_chunk_len(size, i);
      for (uint k = 0; k < n; k++) pkt.write_u8(lf.data[o + k]);
      p5_send(pkt);
      budget--;
    }
  }

  array<uint8> @get = null;
  for (uint d = 0; d < fact_downloads.length(); d++) {
    auto @dl = fact_downloads[d];
    uint count = fact_chunk_count(dl.size);
    int inFlight = 0;
    for (uint i = 0; i < count; i++) {
      if ((dl.have & (uint64(1) << i)) == 0 && dl.asked_ms[i] != 0 && now - dl.asked_ms[i] < facts_resend_ms) inFlight++;
    }
    uint64 ask = 0;
    for (uint i = 0; i < count && inFlight < facts_get_in_flight; i++) {
      if ((dl.have & (uint64(1) << i)) != 0) continue;
      if (dl.asked_ms[i] != 0 && now - dl.asked_ms[i] < facts_resend_ms) continue;
      dl.asked_ms[i] = now;
      ask |= uint64(1) << i;
      inFlight++;
    }
    if (ask == 0) continue;
    if (get is null) @get = p5_packet(p5_fact_get);
    get.write_u16(dl.index);
    get.write_u8(dl.num);
    get.write_u32(uint32(ask & 0xFFFFFFFF));
    get.write_u32(uint32(ask >> 32));
    if (get.length() > 1100) {
      p5_send(get);
      @get = null;
    }
  }
  if (get !is null) p5_send(get);
}

// facts_status records the server's answer to our fact-put.
void facts_status(uint8 num, uint8 state, uint64 received) {
  auto @lf = local_fact(num);
  if (lf is null) return;
  lf.status = true;
  if (state == p5_fact_complete) {
    if (!lf.complete) message("facts: fact " + fmtInt(num) + " uploaded");
    lf.complete = true;
    lf.received = fact_all_chunks(lf.data.length());
  } else if (state == p5_fact_rejected) {
    if (!lf.rejected) message("facts: server rejected fact " + fmtInt(num));
    lf.rejected = true;
  } else {
    lf.received |= received;
  }
}

// facts_list records a player's facts: entries of u8 num, u32 size, 16 byte hash from r[c] to its end.
void facts_list(uint16 index, const array<uint8> &in r, int c) {
  int n = int(r.length());
  while (c + 1 + 4 + int(p5_hash_size) <= n) {
    uint8 num = r[c];
    uint size = p5_u32(r, c + 1);
    array<uint8> hash;
    for (uint k = 0; k < p5_hash_size; k++) hash.insertLast(r[c + 5 + k]);
    c += 5 + p5_hash_size;

    auto @e = fact_listed(index, num);
    if (e is null) {
      @e = FactEntry();
      e.index = index;
      e.num = num;
      fact_lists.insertLast(e);
    }
    e.size = size;
    e.hash = hash;

    if (int(index) == local.index) {
      // our own fact, now known by its hash:
      auto @lf = local_fact(num);
      if (lf !is null && lf.data.length() == size) fact_store_put(hash, lf.data);
    }
  }
}

// facts_data adds a chunk of a fact being downloaded.
void facts_data(uint16 index, uint8 num, uint8 chunk, const array<uint8> &in r, int c) {
  for (uint d = 0; d < fact_downloads.length(); d++) {
    auto @dl = fact_downloads[d];
    if (dl.index != index || dl.num != num) continue;
    uint count = fact_chunk_count(dl.size);
    uint len = r.length() - uint(c);
    if (chunk >= count || len != fact_chunk_len(dl.size, chunk)) return;
    uint o = uint(chunk) * p5_fact_chunk_size;
    for (uint k = 0; k < len; k++) dl.data[o + k] = r[c + k];
    dl.have |= uint64(1) << chunk;
    if (dl.have != fact_all_chunks(dl.size)) return;
    fact_store_put(dl.hash, dl.data);
    fact_downloads.removeAt(d);
    message("facts: player " + fmtInt(index) + " fact " + fmtInt(num) + " downloaded, " + fmtInt(dl.size) + " bytes");
    return;
  }
}

// fact_data returns a remote player's fact if it is here (downloaded, or the same as one we have), else starts
// downloading it and returns null. A fact the player's fact-list doesn't name is asked for with who-is.
array<uint8>@ fact_data(uint16 index, uint8 num) {
  auto @e = fact_listed(index, num);
  if (e is null) {
    p5_send_who_is(index);
    return null;
  }
  auto @s = fact_stored(e.hash);
  if (s !is null) return s.data;
  for (uint d = 0; d < fact_downloads.length(); d++) {
    auto @dl = fact_downloads[d];
    if (dl.index == index && dl.num == num) {
      if (dl.size == e.size && hash_equal(dl.hash, e.hash)) return null;
      fact_downloads.removeAt(d);
      break;
    }
  }
  FactDownload dl;
  dl.index = index;
  dl.num = num;
  dl.size = e.size;
  dl.hash = e.hash;
  dl.data.resize(e.size);
  fact_downloads.insertLast(dl);
  return null;
}

// facts_player_left forgets a player's facts, and the contents no one else has.
void facts_player_left(uint16 index) {
  for (int i = int(fact_lists.length()) - 1; i >= 0; i--) {
    if (fact_lists[i].index == index) fact_lists.removeAt(i);
  }
  for (int i = int(fact_downloads.length()) - 1; i >= 0; i--) {
    if (fact_downloads[i].index == index) fact_downloads.removeAt(i);
  }
  for (int i = int(fact_store.length()) - 1; i >= 0; i--) {
    bool used = false;
    for (uint j = 0; j < fact_lists.length() && !used; j++) {
      if (hash_equal(fact_lists[j].hash, fact_store[i].hash)) used = true;
    }
    if (!used) fact_store.removeAt(i);
  }
}

// build_local_facts builds the local player's facts; see LinkFact.as, FollowerFact.as and SMFact.as.
void build_local_facts() {
  build_link_fact();
  build_follower_fact();
  build_sm_facts();
}

// ChrRow binds chrs [chr, chr+n) to tiles [tile, tile+n) of a fact (one binding of msg_sprite_chrs).
class ChrRow {
  uint8 chr;
  uint8 n;
  uint8 fact;
  uint16 tile;
}
