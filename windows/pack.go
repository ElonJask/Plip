package main

import (
	"encoding/json"
	"math"
	"math/rand"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type rules struct {
	PitchJitter    float64 `json:"pitch_jitter"`
	ComboEnabled   bool    `json:"combo_enabled"`
	ComboPitchStep float64 `json:"combo_pitch_step"`
	ComboTimeoutMs int     `json:"combo_timeout_ms"`
	ComboMaxSteps  int     `json:"combo_max_steps"`
}

type keyMapping struct {
	Files  []string `json:"files"`
	Volume float64  `json:"volume"`
}

type manifest struct {
	Name        string                `json:"name"`
	Version     string                `json:"version"`
	Author      string                `json:"author"`
	Rules       rules                 `json:"rules"`
	KeyMappings map[string]keyMapping `json:"key_mappings"`
}

func (m *manifest) applyDefaults() {
	if m.Rules.PitchJitter == 0 && !m.Rules.ComboEnabled && m.Rules.ComboTimeoutMs == 0 {
		m.Rules.PitchJitter = 0.04
	}
	if m.Rules.ComboTimeoutMs == 0 {
		m.Rules.ComboTimeoutMs = 600
	}
	if m.Rules.ComboPitchStep == 0 {
		m.Rules.ComboPitchStep = 0.05
	}
	if m.Rules.ComboMaxSteps == 0 {
		m.Rules.ComboMaxSteps = 24
	}
	if m.Version == "" {
		m.Version = "1.0.0"
	}
	for name, mapping := range m.KeyMappings {
		if mapping.Volume == 0 {
			mapping.Volume = 0.8
			m.KeyMappings[name] = mapping
		}
	}
}

type soundpack struct {
	ID       string
	Dir      string
	Manifest manifest
}

func loadPack(dir string) (soundpack, error) {
	data, err := os.ReadFile(filepath.Join(dir, "manifest.json"))
	if err != nil {
		return soundpack{}, err
	}
	var decoded manifest
	if err := json.Unmarshal(data, &decoded); err != nil {
		return soundpack{}, err
	}
	decoded.applyDefaults()
	return soundpack{ID: filepath.Base(dir), Dir: dir, Manifest: decoded}, nil
}

func scanPacks(dirs ...string) []soundpack {
	order := []string{}
	byID := map[string]soundpack{}
	for _, dir := range dirs {
		entries, err := os.ReadDir(dir)
		if err != nil {
			continue
		}
		for _, entry := range entries {
			if !entry.IsDir() {
				continue
			}
			pack, err := loadPack(filepath.Join(dir, entry.Name()))
			if err != nil {
				continue
			}
			if _, seen := byID[pack.ID]; !seen {
				order = append(order, pack.ID)
			}
			byID[pack.ID] = pack
		}
	}
	out := make([]soundpack, 0, len(order))
	for _, id := range order {
		out = append(out, byID[id])
	}
	return out
}

type strike struct {
	Path      string
	Semitones float64
	Volume    float64
}

type planner struct {
	combo int
	last  time.Time
	has   bool
}

func (p *planner) reset() {
	p.combo = 0
	p.has = false
}

func (p *planner) plan(pack soundpack, key string, now time.Time, muted, comboOn bool, master float64, rng *rand.Rand) (strike, bool) {
	if muted {
		return strike{}, false
	}
	rules := pack.Manifest.Rules
	if p.has && comboOn && rules.ComboEnabled && now.Sub(p.last) < time.Duration(rules.ComboTimeoutMs)*time.Millisecond {
		if p.combo < rules.ComboMaxSteps {
			p.combo++
		}
	} else {
		p.combo = 0
	}
	p.last = now
	p.has = true

	mapping, ok := pack.Manifest.KeyMappings[key]
	if !ok || len(mapping.Files) == 0 {
		mapping, ok = pack.Manifest.KeyMappings["default"]
	}
	if !ok || len(mapping.Files) == 0 {
		return strike{}, false
	}
	name := mapping.Files[rng.Intn(len(mapping.Files))]
	unit := rng.Float64()
	if rules.PitchJitter == 0 {
		unit = 0.5
	}
	jitter := (unit*2 - 1) * rules.PitchJitter
	semitones := jitter + float64(p.combo)*rules.ComboPitchStep
	volume := mapping.Volume * clamp(master, 0, 1)
	return strike{Path: filepath.Join(pack.Dir, name), Semitones: semitones, Volume: volume}, true
}

func keyName(vk uint16) string {
	switch vk {
	case 0x20:
		return "space"
	case 0x0D:
		return "return"
	case 0x08:
		return "backspace"
	case 0x2E:
		return "forward_delete"
	case 0x10, 0xA0, 0xA1:
		return "shift"
	case 0x14:
		return "capslock"
	case 0x09:
		return "tab"
	case 0x1B:
		return "escape"
	default:
		return "default"
	}
}

func isMuteHotkey(vk uint16, alt, shift, ctrl, win bool) bool {
	return vk == 0x4D && alt && shift && !ctrl && !win
}

func pitchRatio(semitones float64) float64 {
	return math.Pow(2, semitones/12)
}

func resample(samples []int16, semitones float64) []int16 {
	if len(samples) == 0 {
		return nil
	}
	ratio := pitchRatio(semitones)
	outLen := int(math.Floor(float64(len(samples)) / ratio))
	if outLen < 1 {
		outLen = 1
	}
	out := make([]int16, outLen)
	last := len(samples) - 1
	for i := 0; i < outLen; i++ {
		pos := float64(i) * ratio
		idx := int(pos)
		if idx >= last {
			out[i] = samples[last]
			continue
		}
		frac := pos - float64(idx)
		a := float64(samples[idx])
		b := float64(samples[idx+1])
		out[i] = int16(math.Round(a*(1-frac) + b*frac))
	}
	return out
}

func importID(name string) string {
	var b strings.Builder
	for _, r := range strings.ToLower(name) {
		switch {
		case r == ' ':
			b.WriteByte('-')
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9', r == '-':
			b.WriteRune(r)
		}
	}
	if b.Len() == 0 {
		return "pack"
	}
	return b.String()
}

func clamp(v, lo, hi float64) float64 {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}
