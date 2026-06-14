package tray

import (
	"bytes"
	"image"
	"image/color"
	"image/draw"
	"image/png"
	"math"
)

// trayMarginRatio gives breathing room around the content, as a fraction of its
// longest side (1/10 = 10% on each side).
const trayMarginRatio = 10

// processIcon trims the asymmetric transparent padding from the source PNG and
// re-centers the artwork in a square canvas at full resolution. macOS then
// scales the large image down to the menu-bar height so it lines up with the
// native icons next to it. On any failure it returns the original bytes.
func processIcon(src []byte) []byte {
	img, err := png.Decode(bytes.NewReader(src))
	if err != nil {
		return src
	}

	rgba := image.NewRGBA(img.Bounds())
	draw.Draw(rgba, rgba.Bounds(), img, img.Bounds().Min, draw.Src)

	sw := rgba.Bounds().Dx()
	sh := rgba.Bounds().Dy()

	// Bounding box of non-transparent content.
	x0, y0, x1, y1 := sw, sh, 0, 0
	found := false
	for y := 0; y < sh; y++ {
		for x := 0; x < sw; x++ {
			if rgba.RGBAAt(x, y).A > 16 {
				found = true
				if x < x0 {
					x0 = x
				}
				if y < y0 {
					y0 = y
				}
				if x > x1 {
					x1 = x
				}
				if y > y1 {
					y1 = y
				}
			}
		}
	}
	if !found {
		return src // fully transparent — nothing to trim
	}

	contentW := x1 - x0 + 1
	contentH := y1 - y0 + 1

	longest := contentW
	if contentH > longest {
		longest = contentH
	}
	side := longest + 2*(longest/trayMarginRatio)
	offX := (side - contentW) / 2
	offY := (side - contentH) / 2

	dst := image.NewRGBA(image.Rect(0, 0, side, side))
	srcRect := image.Rect(x0, y0, x1+1, y1+1)
	draw.Draw(dst, image.Rect(offX, offY, offX+contentW, offY+contentH), rgba, srcRect.Min, draw.Src)

	var buf bytes.Buffer
	if err := png.Encode(&buf, dst); err != nil {
		return src
	}
	return buf.Bytes()
}

// dotPNG returns a filled circle PNG with sub-pixel antialiasing.
// size should be 28–32 for crisp Retina rendering at menu-item icon size.
func dotPNG(size int, c color.RGBA) []byte {
	img := image.NewRGBA(image.Rect(0, 0, size, size))
	cx, cy := float64(size)/2, float64(size)/2
	r := float64(size)/2 - 1.0

	for y := 0; y < size; y++ {
		for x := 0; x < size; x++ {
			// Sample 4×4 sub-pixels for antialiasing
			var coverage float64
			for sy := 0; sy < 4; sy++ {
				for sx := 0; sx < 4; sx++ {
					px := float64(x) + (float64(sx)+0.5)/4.0
					py := float64(y) + (float64(sy)+0.5)/4.0
					dx := px - cx
					dy := py - cy
					if math.Sqrt(dx*dx+dy*dy) <= r {
						coverage += 1.0 / 16.0
					}
				}
			}
			if coverage > 0 {
				img.SetRGBA(x, y, color.RGBA{
					R: c.R,
					G: c.G,
					B: c.B,
					A: uint8(float64(c.A) * coverage),
				})
			}
		}
	}

	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		return nil
	}
	return buf.Bytes()
}

var (
	// DotGreen and DotRed are pre-rendered status dots for menu items.
	// 16×16 matches the standard macOS menu-item icon size.
	DotGreen = dotPNG(13, color.RGBA{52, 199, 89, 255})
	DotRed   = dotPNG(13, color.RGBA{255, 59, 48, 255})
)
