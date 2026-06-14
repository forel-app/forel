package rules

import (
	"os"
	"path/filepath"
	"testing"
)

func mkRule(name string, enabled bool, match ConditionMatch, conds []Condition) Rule {
	return Rule{
		ID:             name,
		Name:           name,
		Enabled:        enabled,
		ConditionMatch: match,
		Conditions:     conds,
		Actions:        []Action{},
	}
}

func TestEvaluateFileMatchesEnabledRules(t *testing.T) {
	file := tempFile(t, "invoice.pdf", "paid")
	rs := []Rule{
		mkRule("all matched", true, MatchAll, []Condition{
			cond(CondName, OpContains, "invoice"),
			cond(CondExtension, OpIs, "pdf"),
		}),
		mkRule("any matched", true, MatchAny, []Condition{
			cond(CondName, OpContains, "receipt"),
			cond(CondContents, OpContains, "paid"),
		}),
		mkRule("disabled", false, MatchAll, []Condition{
			cond(CondExtension, OpIs, "pdf"),
		}),
		// A rule with no conditions matches every file.
		mkRule("empty", true, MatchAll, nil),
	}

	got := EvaluateFile(file, rs)
	want := []string{"all matched", "any matched", "empty"}
	if len(got) != len(want) || got[0] != want[0] || got[1] != want[1] || got[2] != want[2] {
		t.Fatalf("expected %v, got %v", want, got)
	}
}

func TestPreviewFileHidesAlreadyAppliedActions(t *testing.T) {
	file := tempFile(t, "photo.jpg", "img")
	rule := mkRule("label jpgs", true, MatchAll, []Condition{cond(CondExtension, OpIs, "jpg")})
	rule.Actions = []Action{
		{Kind: ActSetColorLabel, Params: map[string]any{"color": "Yellow"}, Position: 1},
		{Kind: ActAddTag, Params: map[string]any{"tags": []any{"Sorted"}}, Position: 2},
	}

	// Before applying: preview lists both actions.
	if p := PreviewFile(file, []Rule{rule}); p == nil || len(p.Rules[0].Actions) != 2 {
		t.Fatalf("expected 2 actions before applying, got %+v", p)
	}

	// Apply the rule, then preview must be empty — both actions are now no-ops.
	EvaluateFile(file, []Rule{rule})
	if p := PreviewFile(file, []Rule{rule}); p != nil {
		t.Fatalf("expected empty preview after applying, got %+v", p)
	}
}

func TestPreviewFileReturnsOrderedActionsWithoutExecuting(t *testing.T) {
	dir := t.TempDir()
	file := filepath.Join(dir, "invoice.pdf")
	if err := os.WriteFile(file, []byte("paid"), 0o644); err != nil {
		t.Fatal(err)
	}
	destination := filepath.Join(dir, "Processed")
	if err := os.Mkdir(destination, 0o755); err != nil {
		t.Fatal(err)
	}

	rule := mkRule("archive invoice", true, MatchAll, []Condition{
		cond(CondExtension, OpIs, "pdf"),
	})
	rule.Actions = []Action{
		{Kind: ActAddTag, Params: map[string]any{"tags": []any{"Reviewed"}}, Position: 2},
		{Kind: ActMoveToFolder, Params: map[string]any{"destination": destination}, Position: 1},
	}

	preview := PreviewFile(file, []Rule{rule})
	if preview == nil {
		t.Fatal("preview should match")
	}
	if _, err := os.Stat(file); err != nil {
		t.Fatal("file should still exist (no execution)")
	}
	if _, err := os.Stat(filepath.Join(destination, "invoice.pdf")); !os.IsNotExist(err) {
		t.Fatal("file should not have been moved")
	}
	if preview.Name != "invoice.pdf" {
		t.Fatalf("name = %q", preview.Name)
	}
	if preview.Rules[0].RuleName != "archive invoice" {
		t.Fatalf("rule name = %q", preview.Rules[0].RuleName)
	}
	wantActions := []string{
		"Move to " + filepath.Join(destination, "invoice.pdf"),
		"Add tag: Reviewed",
	}
	got := preview.Rules[0].Actions
	if len(got) != len(wantActions) || got[0] != wantActions[0] || got[1] != wantActions[1] {
		t.Fatalf("expected %v, got %v", wantActions, got)
	}
}
