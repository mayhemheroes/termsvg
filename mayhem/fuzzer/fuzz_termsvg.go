// Fuzz target for termsvg's asciicast parser + IR processor + SVG renderer —
// the same code path the CLI's `export`/`play` commands drive on a user file.
package fuzzer

import (
	"bytes"
	"context"
	"testing"

	"github.com/mrmarble/termsvg/pkg/asciicast"
	"github.com/mrmarble/termsvg/pkg/ir"
	"github.com/mrmarble/termsvg/pkg/renderer"
	"github.com/mrmarble/termsvg/pkg/renderer/svg"
)

const (
	maxInput  = 128 << 10 // bound work per input
	maxDimW   = 200
	maxDimH   = 60
	maxEvents = 512
)

func FuzzTermsvg(f *testing.F) {
	f.Fuzz(func(t *testing.T, data []byte) {
		if len(data) > maxInput {
			t.Skip()
		}

		cast, err := asciicast.Parse(bytes.NewReader(data))
		if err != nil {
			t.Skip()
		}

		// Clamp attacker-controlled dimensions/event counts so the terminal
		// emulator and renderer stay within sane memory/time bounds.
		if cast.Header.Width <= 0 || cast.Header.Width > maxDimW {
			cast.Header.Width = 80
		}
		if cast.Header.Height <= 0 || cast.Header.Height > maxDimH {
			cast.Header.Height = 24
		}
		if len(cast.Events) > maxEvents {
			cast.Events = cast.Events[:maxEvents]
		}

		proc := ir.NewProcessor(ir.DefaultProcessorConfig())
		rec, err := proc.Process(cast)
		if err != nil {
			t.Skip()
		}

		var buf bytes.Buffer
		_ = svg.New(renderer.DefaultConfig()).Render(context.Background(), rec, &buf)
	})
}
