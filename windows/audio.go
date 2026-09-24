//go:build windows

package main

import (
	"encoding/binary"
	"math"
	"os"
	"sync"
	"unsafe"

	"golang.org/x/sys/windows"
)

var (
	winmm              = windows.NewLazySystemDLL("winmm.dll")
	procWaveOutOpen    = winmm.NewProc("waveOutOpen")
	procWaveOutPrepare = winmm.NewProc("waveOutPrepareHeader")
	procWaveOutWrite   = winmm.NewProc("waveOutWrite")
	procWaveOutReset   = winmm.NewProc("waveOutReset")
	procWaveOutUnprep  = winmm.NewProc("waveOutUnprepareHeader")
	procWaveOutClose   = winmm.NewProc("waveOutClose")
)

const (
	waveMapper    = 0xFFFFFFFF
	waveFormatPCM = 1
	whdrPrepared  = 0x00000002
	sampleRate    = 44100
	voiceCount    = 8
)

type waveFormat struct {
	Format        uint16
	Channels      uint16
	SamplesPerSec uint32
	AvgBytes      uint32
	BlockAlign    uint16
	Bits          uint16
}

type waveHeader struct {
	Data          uintptr
	BufferLength  uint32
	BytesRecorded uint32
	User          uintptr
	Flags         uint32
	Loops         uint32
	LoopControl   uintptr
	Reserved      uintptr
}

type voice struct {
	handle uintptr
	header waveHeader
	buffer []byte
	ready  bool
}

type player struct {
	mu      sync.Mutex
	voices  [voiceCount]voice
	next    int
	cache   map[string][]int16
	pitched map[pitchKey][]byte
}

type pitchKey struct {
	path  string
	cents int
}

func newPlayer() *player {
	format := waveFormat{
		Format:        waveFormatPCM,
		Channels:      1,
		SamplesPerSec: sampleRate,
		AvgBytes:      sampleRate * 2,
		BlockAlign:    2,
		Bits:          16,
	}
	p := &player{
		cache:   map[string][]int16{},
		pitched: map[pitchKey][]byte{},
	}
	for i := range p.voices {
		var handle uintptr
		r, _, _ := procWaveOutOpen.Call(
			uintptr(unsafe.Pointer(&handle)),
			waveMapper,
			uintptr(unsafe.Pointer(&format)),
			0, 0, 0,
		)
		if r == 0 {
			p.voices[i] = voice{handle: handle, ready: true}
		}
	}
	return p
}

func (p *player) close() {
	p.mu.Lock()
	defer p.mu.Unlock()
	for i := range p.voices {
		v := &p.voices[i]
		if !v.ready {
			continue
		}
		procWaveOutReset.Call(v.handle)
		if v.header.Flags&whdrPrepared != 0 {
			procWaveOutUnprep.Call(v.handle, uintptr(unsafe.Pointer(&v.header)), uintptr(unsafe.Sizeof(v.header)))
		}
		procWaveOutClose.Call(v.handle)
		v.ready = false
	}
}

func (p *player) preload(path string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if _, ok := p.cache[path]; ok {
		return
	}
	if decoded, err := readWAV(path); err == nil {
		p.cache[path] = decoded
	}
}

func (p *player) play(path string, semitones, volume float64) {
	cents := int(math.Round(semitones * 100))
	p.mu.Lock()
	defer p.mu.Unlock()
	samples, ok := p.rendered(path, cents, volume)
	if !ok || len(samples) < 2 {
		return
	}
	for n := 0; n < voiceCount; n++ {
		v := &p.voices[p.next]
		p.next = (p.next + 1) % voiceCount
		if !v.ready {
			continue
		}
		procWaveOutReset.Call(v.handle)
		if v.header.Flags&whdrPrepared != 0 {
			procWaveOutUnprep.Call(v.handle, uintptr(unsafe.Pointer(&v.header)), uintptr(unsafe.Sizeof(v.header)))
			v.header.Flags = 0
		}
		v.buffer = append([]byte(nil), samples...)
		v.header = waveHeader{
			Data:         uintptr(unsafe.Pointer(&v.buffer[0])),
			BufferLength: uint32(len(v.buffer)),
		}
		r, _, _ := procWaveOutPrepare.Call(v.handle, uintptr(unsafe.Pointer(&v.header)), uintptr(unsafe.Sizeof(v.header)))
		if r != 0 {
			continue
		}
		procWaveOutWrite.Call(v.handle, uintptr(unsafe.Pointer(&v.header)), uintptr(unsafe.Sizeof(v.header)))
		return
	}
}

func (p *player) rendered(path string, cents int, volume float64) ([]byte, bool) {
	key := pitchKey{path: path, cents: cents}
	pcm, ok := p.pitched[key]
	if !ok {
		raw, ok := p.cache[path]
		if !ok {
			decoded, err := readWAV(path)
			if err != nil {
				return nil, false
			}
			raw = decoded
			p.cache[path] = raw
		}
		pcm = int16ToBytes(resample(raw, float64(cents)/100))
		p.pitched[key] = pcm
	}
	if volume >= 0.999 {
		return pcm, len(pcm) >= 2
	}
	scaled := make([]byte, len(pcm))
	copy(scaled, pcm)
	gain := clamp(volume, 0, 1)
	for i := 0; i+1 < len(scaled); i += 2 {
		sample := int16(binary.LittleEndian.Uint16(scaled[i:]))
		binary.LittleEndian.PutUint16(scaled[i:], uint16(int16(math.Round(float64(sample)*gain))))
	}
	return scaled, len(scaled) >= 2
}

func int16ToBytes(samples []int16) []byte {
	out := make([]byte, len(samples)*2)
	for i, sample := range samples {
		binary.LittleEndian.PutUint16(out[i*2:], uint16(sample))
	}
	return out
}

func readWAV(path string) ([]int16, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	if len(data) < 44 || string(data[0:4]) != "RIFF" || string(data[8:12]) != "WAVE" {
		return nil, os.ErrInvalid
	}
	var channels, bits uint16
	var rate uint32
	var pcm []byte
	for off := 12; off+8 <= len(data); {
		id := string(data[off : off+4])
		size := int(binary.LittleEndian.Uint32(data[off+4 : off+8]))
		off += 8
		if size < 0 || off+size > len(data) {
			break
		}
		chunk := data[off : off+size]
		if id == "fmt " && len(chunk) >= 16 && binary.LittleEndian.Uint16(chunk[0:]) == waveFormatPCM {
			channels = binary.LittleEndian.Uint16(chunk[2:])
			rate = binary.LittleEndian.Uint32(chunk[4:])
			bits = binary.LittleEndian.Uint16(chunk[14:])
		}
		if id == "data" {
			pcm = chunk
		}
		off += size + size%2
	}
	if channels == 0 || bits != 16 || rate == 0 || len(pcm) < int(channels)*2 {
		return nil, os.ErrInvalid
	}
	frames := len(pcm) / 2 / int(channels)
	mono := make([]int16, frames)
	for i := 0; i < frames; i++ {
		var sum int
		for c := 0; c < int(channels); c++ {
			off := (i*int(channels) + c) * 2
			sum += int(int16(binary.LittleEndian.Uint16(pcm[off:])))
		}
		mono[i] = int16(sum / int(channels))
	}
	if rate == sampleRate {
		return mono, nil
	}
	ratio := float64(rate) / sampleRate
	return resample(mono, math.Log2(ratio)*12), nil
}
