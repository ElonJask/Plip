//go:build windows

package main

import (
	"math/rand"
	"os"
	"path/filepath"
	"sync"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/registry"
)

const (
	whKeyboardLL   = 13
	wmKeydown      = 0x0100
	wmSyskeydown   = 0x0104
	wmApp          = 0x8000
	wmKey          = wmApp + 1
	wmCommand      = 0x0111
	wmRButtonUp    = 0x0205
	wmLButtonUp    = 0x0202
	nimAdd         = 0
	nimDelete      = 2
	nifMessage     = 0x1
	nifIcon        = 0x2
	nifTip         = 0x4
	imageIcon      = 1
	lrLoadFromFile = 0x0010
	mfString       = 0
	mfChecked      = 0x00000008
	tpmRightAlign  = 0x0008
	tpmBottomAlign = 0x0020
	llkhfAltDown   = 0x20
	idMute         = 1001
	idCombo        = 1002
	idExit         = 1003
)

var (
	user32            = windows.NewLazySystemDLL("user32.dll")
	shell32           = windows.NewLazySystemDLL("shell32.dll")
	kernel32          = windows.NewLazySystemDLL("kernel32.dll")
	procCallNext      = user32.NewProc("CallNextHookEx")
	procSetHook       = user32.NewProc("SetWindowsHookExW")
	procUnhook        = user32.NewProc("UnhookWindowsHookEx")
	procGetMessage    = user32.NewProc("GetMessageW")
	procTranslate     = user32.NewProc("TranslateMessage")
	procDispatch      = user32.NewProc("DispatchMessageW")
	procPostMessage   = user32.NewProc("PostMessageW")
	procPostQuit      = user32.NewProc("PostQuitMessage")
	procGetAsync      = user32.NewProc("GetAsyncKeyState")
	procGetModule     = kernel32.NewProc("GetModuleHandleW")
	procLoadImage     = user32.NewProc("LoadImageW")
	procShellNotify   = shell32.NewProc("Shell_NotifyIconW")
	procCreatePopup   = user32.NewProc("CreatePopupMenu")
	procAppendMenu    = user32.NewProc("AppendMenuW")
	procTrackPopup    = user32.NewProc("TrackPopupMenu")
	procDestroyMenu   = user32.NewProc("DestroyMenu")
	procSetForeground = user32.NewProc("SetForegroundWindow")
	procGetCursor     = user32.NewProc("GetCursorPos")
	procCreateWindow  = user32.NewProc("CreateWindowExW")
	procDefWindowProc = user32.NewProc("DefWindowProcW")
	procRegisterClass = user32.NewProc("RegisterClassExW")
	procMessageBox    = user32.NewProc("MessageBoxW")
)

type point struct{ X, Y int32 }

type msg struct {
	HWND    uintptr
	Message uint32
	WParam  uintptr
	LParam  uintptr
	Time    uint32
	Pt      point
}

type kbdLL struct {
	VkCode      uint32
	ScanCode    uint32
	Flags       uint32
	Time        uint32
	DwExtraInfo uintptr
}

type notifyIcon struct {
	Size            uint32
	Wnd             uintptr
	ID              uint32
	Flags           uint32
	CallbackMessage uint32
	Icon            uintptr
	Tip             [128]uint16
}

type wndClass struct {
	Size       uint32
	Style      uint32
	WndProc    uintptr
	ClsExtra   int32
	WndExtra   int32
	Instance   uintptr
	Icon       uintptr
	Cursor     uintptr
	Background uintptr
	MenuName   *uint16
	ClassName  *uint16
	IconSm     uintptr
}

type app struct {
	mu      sync.Mutex
	packs   []soundpack
	index   int
	muted   bool
	combo   bool
	volume  float64
	planner planner
	player  *player
	rng     *rand.Rand
	hwnd    uintptr
	hook    uintptr
	icon    uintptr
}

func main() {
	exe, err := os.Executable()
	if err != nil {
		fatal(err.Error())
	}
	root := filepath.Join(filepath.Dir(exe), "Soundpacks")
	config, err := os.UserConfigDir()
	if err != nil {
		fatal(err.Error())
	}
	userPacks := filepath.Join(config, "Plip", "Soundpacks")
	_ = os.MkdirAll(userPacks, 0o755)
	packs := scanPacks(root, userPacks)
	if len(packs) == 0 {
		fatal("没有找到音效包。把 Plip.exe 和 Soundpacks 放在同一层。")
	}
	application = &app{
		packs:  packs,
		combo:  true,
		volume: 0.8,
		player: newPlayer(),
		rng:    rand.New(rand.NewSource(time.Now().UnixNano())),
	}
	application.loadSettings()
	application.preload()
	application.run()
}

var application *app

func (a *app) run() {
	instance, _, _ := procGetModule.Call(0)
	className, _ := windows.UTF16PtrFromString("PlipTray")
	class := wndClass{
		WndProc:   windows.NewCallback(wndProc),
		Instance:  instance,
		ClassName: className,
	}
	class.Size = uint32(unsafe.Sizeof(class))
	if r, _, _ := procRegisterClass.Call(uintptr(unsafe.Pointer(&class))); r == 0 {
		fatal("无法注册窗口。")
	}
	windowName, _ := windows.UTF16PtrFromString("Plip")
	hwnd, _, _ := procCreateWindow.Call(0, uintptr(unsafe.Pointer(className)), uintptr(unsafe.Pointer(windowName)), 0, 0, 0, 0, 0, 0, 0, instance, 0)
	if hwnd == 0 {
		fatal("无法创建托盘窗口。")
	}
	a.hwnd = hwnd
	iconPath, _ := windows.UTF16PtrFromString(a.iconPath())
	icon, _, _ := procLoadImage.Call(0, uintptr(unsafe.Pointer(iconPath)), imageIcon, 0, 0, lrLoadFromFile)
	a.icon = icon
	a.addIcon()

	hook, _, _ := procSetHook.Call(whKeyboardLL, windows.NewCallback(keyboardProc), instance, 0)
	a.hook = hook
	if hook == 0 {
		fatal("无法安装键盘钩子。")
	}
	defer procUnhook.Call(hook)
	defer a.removeIcon()
	defer a.player.close()

	var message msg
	for {
		ret, _, _ := procGetMessage.Call(uintptr(unsafe.Pointer(&message)), 0, 0, 0)
		if int32(ret) <= 0 {
			return
		}
		procTranslate.Call(uintptr(unsafe.Pointer(&message)))
		procDispatch.Call(uintptr(unsafe.Pointer(&message)))
	}
}

func keyboardProc(code int32, wParam, lParam uintptr) uintptr {
	next := uintptr(0)
	if application != nil {
		next = application.hook
		if code >= 0 && (wParam == wmKeydown || wParam == wmSyskeydown) && application.hwnd != 0 {
			info := (*kbdLL)(unsafe.Pointer(lParam))
			procPostMessage.Call(application.hwnd, wmKey, uintptr(info.VkCode), uintptr(info.Flags))
		}
	}
	ret, _, _ := procCallNext.Call(next, uintptr(code), wParam, lParam)
	return ret
}

func (a *app) key(vk uint16, flags uint32) {
	alt := flags&llkhfAltDown != 0
	shift := vkState(0x10)
	ctrl := vkState(0x11)
	win := vkState(0x5B) || vkState(0x5C)
	if isMuteHotkey(vk, alt, shift, ctrl, win) {
		a.muted = !a.muted
		a.saveSettingsLocked()
		return
	}
	if a.index < 0 || a.index >= len(a.packs) {
		return
	}
	hit, ok := a.planner.plan(a.packs[a.index], keyName(vk), time.Now(), a.muted, a.combo, a.volume, a.rng)
	if ok {
		a.player.play(hit.Path, hit.Semitones, hit.Volume)
	}
}

func vkState(vk int) bool {
	state, _, _ := procGetAsync.Call(uintptr(vk))
	return state&0x8000 != 0
}

func wndProc(hwnd, msgID, wParam, lParam uintptr) uintptr {
	if application == nil {
		ret, _, _ := procDefWindowProc.Call(hwnd, msgID, wParam, lParam)
		return ret
	}
	switch msgID {
	case wmApp:
		if lParam == wmRButtonUp || lParam == wmLButtonUp {
			application.menu()
			return 0
		}
	case wmKey:
		application.mu.Lock()
		application.key(uint16(wParam), uint32(lParam))
		application.mu.Unlock()
		return 0
	case wmCommand:
		switch wParam {
		case idMute:
			application.toggleMute()
		case idCombo:
			application.toggleCombo()
		case idExit:
			procPostQuit.Call(0)
		default:
			if wParam >= 2000 {
				application.choose(int(wParam - 2000))
			}
		}
		return 0
	}
	ret, _, _ := procDefWindowProc.Call(hwnd, msgID, wParam, lParam)
	return ret
}

func (a *app) menu() {
	type item struct {
		id    uintptr
		label string
		check bool
	}
	a.mu.Lock()
	items := make([]item, 0, len(a.packs)+3)
	for i, pack := range a.packs {
		items = append(items, item{id: uintptr(2000 + i), label: pack.Manifest.Name, check: i == a.index})
	}
	mute := "静音  Alt+Shift+M"
	if a.muted {
		mute = "取消静音  Alt+Shift+M"
	}
	items = append(items, item{id: idMute, label: mute})
	items = append(items, item{id: idCombo, label: "连击升调", check: a.combo})
	items = append(items, item{id: idExit, label: "退出"})
	a.mu.Unlock()

	menu, _, _ := procCreatePopup.Call()
	for _, item := range items {
		flags := uintptr(mfString)
		if item.check {
			flags |= mfChecked
		}
		name, _ := windows.UTF16PtrFromString(item.label)
		procAppendMenu.Call(menu, flags, item.id, uintptr(unsafe.Pointer(name)))
	}
	var cursor point
	procGetCursor.Call(uintptr(unsafe.Pointer(&cursor)))
	procSetForeground.Call(a.hwnd)
	procTrackPopup.Call(menu, tpmRightAlign|tpmBottomAlign, uintptr(cursor.X), uintptr(cursor.Y), 0, a.hwnd, 0)
	procDestroyMenu.Call(menu)
}

func (a *app) toggleMute() {
	a.mu.Lock()
	a.muted = !a.muted
	a.saveSettingsLocked()
	a.mu.Unlock()
}

func (a *app) toggleCombo() {
	a.mu.Lock()
	a.combo = !a.combo
	a.planner.reset()
	a.saveSettingsLocked()
	a.mu.Unlock()
}

func (a *app) choose(index int) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if index < 0 || index >= len(a.packs) || index == a.index {
		return
	}
	a.index = index
	a.planner.reset()
	a.saveSettingsLocked()
	pack := a.packs[index]
	preview := planner{}
	hit, ok := preview.plan(pack, "default", time.Now(), false, false, a.volume, a.rng)
	if ok {
		a.player.play(hit.Path, hit.Semitones, hit.Volume)
	}
}

func (a *app) preload() {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.index < 0 || a.index >= len(a.packs) {
		return
	}
	for _, mapping := range a.packs[a.index].Manifest.KeyMappings {
		for _, name := range mapping.Files {
			a.player.preload(filepath.Join(a.packs[a.index].Dir, name))
		}
	}
}

func (a *app) addIcon() {
	tip, _ := windows.UTF16FromString("Plip")
	var data notifyIcon
	data.Size = uint32(unsafe.Sizeof(data))
	data.Wnd = a.hwnd
	data.ID = 1
	data.Flags = nifMessage | nifIcon | nifTip
	data.CallbackMessage = wmApp
	data.Icon = a.icon
	copy(data.Tip[:], tip)
	procShellNotify.Call(nimAdd, uintptr(unsafe.Pointer(&data)))
}

func (a *app) removeIcon() {
	var data notifyIcon
	data.Size = uint32(unsafe.Sizeof(data))
	data.Wnd = a.hwnd
	data.ID = 1
	procShellNotify.Call(nimDelete, uintptr(unsafe.Pointer(&data)))
}

func (a *app) iconPath() string {
	exe, _ := os.Executable()
	return filepath.Join(filepath.Dir(exe), "plip.ico")
}

func fatal(text string) {
	body, _ := windows.UTF16PtrFromString(text)
	title, _ := windows.UTF16PtrFromString("Plip")
	procMessageBox.Call(0, uintptr(unsafe.Pointer(body)), uintptr(unsafe.Pointer(title)), 0x00000010)
	os.Exit(1)
}

func (a *app) loadSettings() {
	key, err := registry.OpenKey(registry.CURRENT_USER, `Software\Plip`, registry.QUERY_VALUE)
	if err != nil {
		return
	}
	defer key.Close()
	if v, _, err := key.GetIntegerValue("Muted"); err == nil {
		a.muted = v != 0
	}
	if v, _, err := key.GetIntegerValue("Combo"); err == nil {
		a.combo = v != 0
	}
	if name, _, err := key.GetStringValue("Pack"); err == nil {
		for i, pack := range a.packs {
			if pack.ID == name {
				a.index = i
			}
		}
	}
}

func (a *app) saveSettingsLocked() {
	key, _, err := registry.CreateKey(registry.CURRENT_USER, `Software\Plip`, registry.SET_VALUE)
	if err != nil {
		return
	}
	defer key.Close()
	muted := uint32(0)
	if a.muted {
		muted = 1
	}
	combo := uint32(0)
	if a.combo {
		combo = 1
	}
	_ = key.SetDWordValue("Muted", muted)
	_ = key.SetDWordValue("Combo", combo)
	if a.index >= 0 && a.index < len(a.packs) {
		_ = key.SetStringValue("Pack", a.packs[a.index].ID)
	}
}
