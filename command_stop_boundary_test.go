package cli

import (
	"context"
	"io"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestCommand_StopOnNthArg_PreservesBoundaryTokens(t *testing.T) {
	tests := []struct {
		name string
		stop *int
		args []string
		want []string
		set  bool
	}{
		{
			name: "zero with empty argument",
			stop: intPtr(0),
			args: []string{"", "--verbose", "tail"},
			want: []string{"", "--verbose", "tail"},
		},
		{
			name: "zero with whitespace argument",
			stop: intPtr(0),
			args: []string{" \t ", "--verbose", "tail"},
			want: []string{" \t ", "--verbose", "tail"},
		},
		{
			name: "zero with separator",
			stop: intPtr(0),
			args: []string{"--", "--verbose", "tail"},
			want: []string{"--", "--verbose", "tail"},
		},
		{
			name: "empty argument after boundary",
			stop: intPtr(1),
			args: []string{"host", "", "--verbose", "tail"},
			want: []string{"host", "", "--verbose", "tail"},
		},
		{
			name: "whitespace argument after boundary",
			stop: intPtr(1),
			args: []string{"host", " \t ", "--verbose", "tail"},
			want: []string{"host", " \t ", "--verbose", "tail"},
		},
		{
			name: "separator after boundary",
			stop: intPtr(1),
			args: []string{"host", "--", "--verbose", "tail"},
			want: []string{"host", "--", "--verbose", "tail"},
		},
		{
			name: "empty arguments count toward boundary",
			stop: intPtr(2),
			args: []string{"", " \t ", "", "--verbose", "tail"},
			want: []string{"", " \t ", "", "--verbose", "tail"},
		},
		{
			name: "separator before boundary",
			stop: intPtr(2),
			args: []string{"host", "--", "--verbose", "tail"},
			want: []string{"host", "--verbose", "tail"},
		},
		{
			name: "normal parsing with empty arguments",
			args: []string{"", " \t ", "--verbose", "tail"},
			want: []string{"", " \t ", "tail"},
			set:  true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			for _, nested := range []bool{false, true} {
				name := "root"
				if nested {
					name = "subcommand"
				}
				t.Run(name, func(t *testing.T) {
					called := false
					verbose := &BoolFlag{Name: "verbose"}
					cmd := &Command{
						Name: "exec", StopOnNthArg: tt.stop,
						Flags: []Flag{verbose},
						Writer: io.Discard, ErrWriter: io.Discard,
						Action: func(_ context.Context, c *Command) error {
							called = true
							assert.Equal(t, tt.want, c.Args().Slice())
							assert.Equal(t, tt.set, c.Bool("verbose"))
							assert.Equal(t, tt.set, c.IsSet("verbose"))
							return nil
						},
					}
					args := append([]string{"exec"}, tt.args...)
					if nested {
						cmd = &Command{Name: "tool", Commands: []*Command{cmd}, Writer: io.Discard, ErrWriter: io.Discard}
						args = append([]string{"tool"}, args...)
					}
					require.NoError(t, cmd.Run(buildTestContext(t), args))
					assert.True(t, called)
				})
			}
		})
	}
}

func TestCommand_StopOnNthArg_PersistentFlagsBeforeBoundary(t *testing.T) {
	var got []string
	var value string
	var beforeCalls, flagCalls, actionCalls int
	root := &Command{
		Name: "tool", Writer: io.Discard, ErrWriter: io.Discard,
		Flags: []Flag{&StringFlag{
			Name: "value", Destination: &value,
			Action: func(_ context.Context, _ *Command, v string) error {
				flagCalls++
				assert.Equal(t, "before", v)
				return nil
			},
		}},
		Commands: []*Command{{
			Name: "exec", StopOnNthArg: intPtr(1),
			Before: func(ctx context.Context, _ *Command) (context.Context, error) {
				beforeCalls++
				return ctx, nil
			},
			Action: func(_ context.Context, c *Command) error {
				actionCalls++
				got = c.Args().Slice()
				assert.Equal(t, "before", c.String("value"))
				return nil
			},
		}},
	}
	require.NoError(t, root.Run(buildTestContext(t), []string{"tool", "exec", "--value", "before", "host", "", "--value", "after"}))
	assert.Equal(t, []string{"host", "", "--value", "after"}, got)
	assert.Equal(t, "before", value)
	assert.Equal(t, 1, beforeCalls)
	assert.Equal(t, 1, flagCalls)
	assert.Equal(t, 1, actionCalls)
}
