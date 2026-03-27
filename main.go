package main

/*
#cgo CFLAGS: -x objective-c -fobjc-arc -mmacosx-version-min=11.0
#cgo LDFLAGS: -framework Cocoa -framework Carbon -framework CoreGraphics -framework CoreImage -framework QuartzCore
#include "app.h"
*/
import "C"

func main() {
	C.RunApp()
}
