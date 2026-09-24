//go:build windows

package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"time"
	"unsafe"

	"github.com/jchv/go-webview2/pkg/edge"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/registry"
)

const (
	wsPopup        = 0x80000000
	wsExToolWindow = 0x00000080
	wsExTopmost    = 0x00000008
	wsExNoActivate = 0x08000000
	wmSize         = 0x0005
	swShow         = 5
	swHide         = 0
	runValue       = `Software\Microsoft\Windows\CurrentVersion\Run`
)

var (
	procShowWindow      = user32.NewProc("ShowWindow")
	procMoveWindow      = user32.NewProc("MoveWindow")
	procGetWindowRect   = user32.NewProc("GetWindowRect")
	procSetWindowPos    = user32.NewProc("SetWindowPos")
	procIsWindowVisible = user32.NewProc("IsWindowVisible")
	procBrowse          = shell32.NewProc("SHBrowseForFolderW")
	procPathFromPIDL    = shell32.NewProc("SHGetPathFromIDListW")
	procILFree          = shell32.NewProc("ILFree")
	comdlg              = windows.NewLazySystemDLL("comdlg32.dll")
	procOpenFile        = comdlg.NewProc("GetOpenFileNameW")
)

type rect struct{ Left, Top, Right, Bottom int32 }

type panelMessage struct {
	Action string          `json:"action"`
	Value  json.RawMessage `json:"value"`
}

type panelState struct {
	PackName      string     `json:"packName"`
	PackID        string     `json:"packID"`
	Packs         []packItem `json:"packs"`
	Volume        float64    `json:"volume"`
	Muted         bool       `json:"muted"`
	Combo         bool       `json:"combo"`
	SmartMute     bool       `json:"smartMute"`
	Accessibility bool       `json:"accessibility"`
	Login         bool       `json:"login"`
	LoginMessage  string     `json:"loginMessage"`
	Apps          []appItem  `json:"apps"`
}

type packItem struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

type appItem struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

func (a *app) openPanel() {
	if a.panel != 0 && windowVisible(a.panel) {
		procShowWindow.Call(a.panel, swHide)
		return
	}
	if a.panel == 0 {
		a.createPanel()
	}
	if a.panel == 0 {
		return
	}
	var cursor point
	procGetCursor.Call(uintptr(unsafe.Pointer(&cursor)))
	height := int32(a.panelHeight)
	procSetWindowPos.Call(a.panel, uintptr(^uint32(0)), uintptr(cursor.X-134), uintptr(cursor.Y-height-28), 268, uintptr(height), 0x0040)
	procShowWindow.Call(a.panel, swShow)
	a.publishPanel()
}

func windowVisible(hwnd uintptr) bool {
	shown, _, _ := procIsWindowVisible.Call(hwnd)
	return shown != 0
}

func (a *app) createPanel() {
	className, _ := windows.UTF16PtrFromString("PlipPanel")
	class := wndClass{
		WndProc:   windows.NewCallback(panelProc),
		Instance:  moduleHandle(),
		ClassName: className,
	}
	class.Size = uint32(unsafe.Sizeof(class))
	procRegisterClass.Call(uintptr(unsafe.Pointer(&class)))
	title, _ := windows.UTF16PtrFromString("Plip")
	hwnd, _, _ := procCreateWindow.Call(
		wsExToolWindow|wsExTopmost|wsExNoActivate,
		uintptr(unsafe.Pointer(className)),
		uintptr(unsafe.Pointer(title)),
		wsPopup,
		0, 0, 268, uintptr(a.panelHeight),
		0, 0, moduleHandle(), 0,
	)
	if hwnd == 0 {
		return
	}
	browser := edge.NewChromium()
	browser.DataPath = filepath.Join(a.userPacks, "..", "WebView2")
	browser.SetPermission(edge.CoreWebView2PermissionKindClipboardRead, edge.CoreWebView2PermissionStateAllow)
	if !browser.Embed(hwnd) {
		return
	}
	browser.Resize()
	browser.Init(`window.plip = new Proxy({}, { get: (_, name) => (value) =>
		window.chrome.webview.postMessage(JSON.stringify({ action: name, value })) });`)
	browser.MessageCallback = func(message string) {
		var body panelMessage
		if json.Unmarshal([]byte(message), &body) != nil {
			return
		}
		a.handlePanel(body.Action, body.Value)
	}
	panel := filepath.Join(filepath.Dir(a.bundled), "panel.html")
	browser.Navigate("file:///" + strings.ReplaceAll(panel, `\`, `/`))
	a.panel = hwnd
	a.browser = browser
}

func moduleHandle() uintptr {
	handle, _, _ := procGetModule.Call(0)
	return handle
}

func panelProc(hwnd, msgID, wParam, lParam uintptr) uintptr {
	if application != nil && msgID == wmSize && application.browser != nil {
		application.browser.Resize()
	}
	ret, _, _ := procDefWindowProc.Call(hwnd, msgID, wParam, lParam)
	return ret
}

func (a *app) publishPanel() {
	if a.browser == nil {
		return
	}
	a.mu.Lock()
	state := a.snapshotLocked()
	a.mu.Unlock()
	data, err := json.Marshal(state)
	if err != nil {
		return
	}
	a.browser.Eval("plipRender(" + string(data) + ")")
}

func (a *app) snapshotLocked() panelState {
	items := make([]packItem, len(a.packs))
	name, id := "无音效", ""
	for i, pack := range a.packs {
		items[i] = packItem{ID: pack.ID, Name: pack.Manifest.Name}
		if i == a.index {
			name, id = pack.Manifest.Name, pack.ID
		}
	}
	apps := make([]appItem, len(a.blocklist))
	for i, item := range a.blocklist {
		apps[i] = appItem{ID: item, Name: item}
	}
	return panelState{
		PackName: name, PackID: id, Packs: items,
		Volume: a.volume, Muted: a.muted, Combo: a.combo, SmartMute: a.smart,
		Accessibility: true, Login: startupOn(), Apps: apps,
	}
}

func (a *app) handlePanel(action string, raw json.RawMessage) {
	switch action {
	case "ready":
		a.publishPanel()
	case "resize":
		var height float64
		if json.Unmarshal(raw, &height) == nil && height > 120 {
			a.panelHeight = int(height)
		}
	case "setVolume":
		var value float64
		if json.Unmarshal(raw, &value) == nil {
			a.mu.Lock()
			a.volume = clamp(value, 0, 1)
			a.saveSettingsLocked()
			a.mu.Unlock()
		}
	case "setMuted":
		a.setBool(raw, func(v bool) { a.muted = v })
	case "setCombo":
		a.setBool(raw, func(v bool) { a.combo = v; a.planner.reset() })
	case "setSmartMute":
		a.setBool(raw, func(v bool) { a.smart = v })
	case "setLogin":
		setStartup(boolValue(raw))
		a.publishPanel()
	case "selectPack":
		var id string
		if json.Unmarshal(raw, &id) == nil {
			a.chooseID(id)
		}
	case "removeApp":
		var id string
		if json.Unmarshal(raw, &id) == nil {
			a.removeBlocked(id)
		}
	case "pickApp":
		if name := browseApp(); name != "" {
			a.mu.Lock()
			a.blocklist = append(a.blocklist, name)
			a.saveSettingsLocked()
			a.mu.Unlock()
			a.publishPanel()
		}
	case "importPack":
		if dir := browseFolder(); dir != "" {
			a.importFolder(dir)
			a.publishPanel()
		}
	case "quit":
		procPostQuit.Call(0)
	}
}

func (a *app) setBool(raw json.RawMessage, apply func(bool)) {
	a.mu.Lock()
	apply(boolValue(raw))
	a.saveSettingsLocked()
	a.mu.Unlock()
}

func boolValue(raw json.RawMessage) bool {
	var value bool
	_ = json.Unmarshal(raw, &value)
	return value
}

func (a *app) chooseID(id string) {
	a.mu.Lock()
	defer a.mu.Unlock()
	for i, pack := range a.packs {
		if pack.ID != id {
			continue
		}
		if i == a.index {
			return
		}
		a.index = i
		a.planner.reset()
		a.saveSettingsLocked()
		preview := planner{}
		hit, ok := preview.plan(a.packs[i], "default", time.Now(), false, false, a.volume, a.rng)
		if ok {
			a.player.play(hit.Path, hit.Semitones, hit.Volume)
		}
		return
	}
}

func (a *app) removeBlocked(id string) {
	a.mu.Lock()
	next := a.blocklist[:0]
	for _, item := range a.blocklist {
		if item != id {
			next = append(next, item)
		}
	}
	a.blocklist = next
	a.saveSettingsLocked()
	a.mu.Unlock()
	a.publishPanel()
}

func startupOn() bool {
	key, err := registry.OpenKey(registry.CURRENT_USER, runValue, registry.QUERY_VALUE)
	if err != nil {
		return false
	}
	defer key.Close()
	_, _, err = key.GetStringValue("Plip")
	return err == nil
}

func setStartup(on bool) {
	key, _, err := registry.CreateKey(registry.CURRENT_USER, runValue, registry.SET_VALUE)
	if err != nil {
		return
	}
	defer key.Close()
	if !on {
		_ = key.DeleteValue("Plip")
		return
	}
	if exe, err := os.Executable(); err == nil {
		_ = key.SetStringValue("Plip", exe)
	}
}

type browseInfo struct {
	Owner       uintptr
	Root        uintptr
	DisplayName *uint16
	Title       *uint16
	Flags       uint32
	Callback    uintptr
	Param       uintptr
	Image       int32
}

func browseFolder() string {
	title, _ := windows.UTF16PtrFromString("选择音效包文件夹")
	info := browseInfo{Owner: application.panel, Title: title, Flags: 0x00000041}
	pidl, _, _ := procBrowse.Call(uintptr(unsafe.Pointer(&info)))
	if pidl == 0 {
		return ""
	}
	defer procILFree.Call(pidl)
	var result [260]uint16
	procPathFromPIDL.Call(pidl, uintptr(unsafe.Pointer(&result[0])))
	return windows.UTF16ToString(result[:])
}

type openFileName struct {
	StructSize      uint32
	Owner           uintptr
	Instance        uintptr
	Filter          *uint16
	CustomFilter    *uint16
	MaxCustomFilter uint32
	FilterIndex     uint32
	File            *uint16
	MaxFile         uint32
	FileTitle       *uint16
	MaxFileTitle    uint32
	InitialDir      *uint16
	Title           *uint16
	Flags           uint32
	FileOffset      uint16
	FileExtension   uint16
	DefExt          *uint16
	CustData        uintptr
	FnHook          uintptr
	TemplateName    *uint16
	PvReserved      uintptr
	DwReserved      uint32
	FlagsEx         uint32
}

func browseApp() string {
	title, _ := windows.UTF16PtrFromString("选择应用")
	filter, _ := windows.UTF16PtrFromString("程序\x00*.exe\x00\x00")
	var file [260]uint16
	dialog := openFileName{
		StructSize: uint32(unsafe.Sizeof(openFileName{})),
		Owner:      application.panel,
		Filter:     filter,
		File:       &file[0],
		MaxFile:    uint32(len(file)),
		Title:      title,
		Flags:      0x00080000 | 0x00001000,
	}
	if ret, _, _ := procOpenFile.Call(uintptr(unsafe.Pointer(&dialog))); ret == 0 {
		return ""
	}
	return strings.TrimSuffix(filepath.Base(windows.UTF16ToString(file[:])), ".exe")
}

func (a *app) importFolder(dir string) {
	id := importID(filepath.Base(dir))
	root := filepath.Join(a.userPacks, id)
	_ = os.MkdirAll(root, 0o755)
	entries, _ := os.ReadDir(dir)
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		data, err := os.ReadFile(filepath.Join(dir, entry.Name()))
		if err == nil {
			_ = os.WriteFile(filepath.Join(root, entry.Name()), data, 0o644)
		}
	}
	if _, err := os.Stat(filepath.Join(root, "manifest.json")); err != nil {
		_ = writeSimpleManifest(root, filepath.Base(dir))
	}
	a.mu.Lock()
	a.packs = scanPacks(a.bundled, a.userPacks)
	for i, pack := range a.packs {
		if pack.ID == id && i != a.index {
			a.index = i
			a.planner.reset()
			a.saveSettingsLocked()
		}
	}
	a.mu.Unlock()
}

func writeSimpleManifest(dir, name string) error {
	entries, _ := os.ReadDir(dir)
	files := []string{}
	for _, entry := range entries {
		switch strings.ToLower(filepath.Ext(entry.Name())) {
		case ".wav", ".mp3", ".aiff", ".aif", ".m4a", ".caf":
			files = append(files, entry.Name())
		}
	}
	if len(files) == 0 {
		return os.ErrNotExist
	}
	body, _ := json.MarshalIndent(map[string]any{
		"name": name,
		"key_mappings": map[string]any{"default": map[string]any{"files": files, "volume": 0.85}},
	}, "", "  ")
	return os.WriteFile(filepath.Join(dir, "manifest.json"), body, 0o644)
}
