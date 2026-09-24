package main

import (
	"math"
	"math/rand"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestKeyAndHotkey(t *testing.T) {
	if keyName(0x20) != "space" || keyName(0x0D) != "return" || keyName(0x08) != "backspace" {
		t.Fatal(keyName(0x20), keyName(0x0D), keyName(0x08))
	}
	if keyName(0x41) != "default" {
		t.Fatal(keyName(0x41))
	}
	if !isMuteHotkey(0x4D, true, true, false, false) {
		t.Fatal("expected mute")
	}
	if isMuteHotkey(0x4D, true, true, true, false) || isMuteHotkey(0x41, true, true, false, false) {
		t.Fatal("unexpected mute")
	}
}

func TestComboAndMute(t *testing.T) {
	dir := t.TempDir()
	writePack(t, dir, `{
		"name":"连击",
		"rules":{"pitch_jitter":0,"combo_enabled":true,"combo_pitch_step":0.35,"combo_timeout_ms":500,"combo_max_steps":16},
		"key_mappings":{"default":{"files":["a.wav","b.wav"],"volume":0.8}}
	}`)
	pack, err := loadPack(dir)
	if err != nil {
		t.Fatal(err)
	}
	var planner planner
	rng := rand.New(rand.NewSource(1))
	now := time.Unix(10, 0)
	first, ok := planner.plan(pack, "default", now, false, true, 1, rng)
	if !ok || planner.combo != 0 || first.Semitones != 0 {
		t.Fatalf("first %+v combo %d", first, planner.combo)
	}
	second, ok := planner.plan(pack, "default", now.Add(200*time.Millisecond), false, true, 1, rng)
	if !ok || planner.combo != 1 || math.Abs(second.Semitones-0.35) > 0.001 {
		t.Fatalf("second %+v combo %d", second, planner.combo)
	}
	if _, ok := planner.plan(pack, "default", now.Add(time.Second), true, true, 1, rng); ok {
		t.Fatal("muted strike played")
	}
}

func TestUserPackOverridesBundled(t *testing.T) {
	root := t.TempDir()
	bundled := filepath.Join(root, "bundled", "blue")
	user := filepath.Join(root, "user", "blue")
	writePack(t, bundled, `{"name":"内置","key_mappings":{"default":{"files":["a.wav"]}}}`)
	writePack(t, user, `{"name":"我的","key_mappings":{"default":{"files":["a.wav"]}}}`)
	packs := scanPacks(filepath.Join(root, "bundled"), filepath.Join(root, "user"))
	if len(packs) != 1 || packs[0].Manifest.Name != "我的" {
		t.Fatalf("%+v", packs)
	}
}

func TestResampleShortens(t *testing.T) {
	in := []int16{0, 1000, 2000, 1000, 0, -1000, -2000, -1000}
	if len(resample(nil, 12)) != 0 {
		t.Fatal("empty")
	}
	same := resample(in, 0)
	if len(same) != len(in) || same[0] != 0 {
		t.Fatalf("%v", same)
	}
	up := resample(in, 12)
	if len(up) >= len(in) || len(up) == 0 {
		t.Fatalf("len %d", len(up))
	}
}

func TestRealPacks(t *testing.T) {
	root := filepath.Join("..", "Soundpacks")
	entries, err := os.ReadDir(root)
	if err != nil {
		t.Fatal(err)
	}
	count := 0
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		count++
		pack, err := loadPack(filepath.Join(root, entry.Name()))
		if err != nil {
			t.Fatal(entry.Name(), err)
		}
		if len(pack.Manifest.KeyMappings["default"].Files) == 0 {
			t.Fatal(entry.Name(), "missing default")
		}
		for _, mapping := range pack.Manifest.KeyMappings {
			for _, name := range mapping.Files {
				if _, err := os.Stat(filepath.Join(pack.Dir, name)); err != nil {
					t.Fatal(name, err)
				}
			}
		}
	}
	if count != 13 {
		t.Fatal(count)
	}
}

func writePack(t *testing.T, dir, body string) {
	t.Helper()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "manifest.json"), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "a.wav"), []byte("RIFF"), 0o644); err != nil {
		t.Fatal(err)
	}
}
