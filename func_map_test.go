package admin

import (
	"fmt"
	"html/template"
	"testing"

	"github.com/fatih/color"
	"github.com/jinzhu/gorm"
	"github.com/qor/qor"
)

type rawTestCase struct {
	HTML         string
	ExpectResult string
}

func TestFuncMaps(t *testing.T) {
	rawTestCases := []rawTestCase{
		{HTML: "<a href='#'>Hello</a>", ExpectResult: "Hello"},
		{HTML: "<a href='http://www.google.com'>Hello</a>", ExpectResult: "<a href=\"http://www.google.com\" rel=\"nofollow\">Hello</a>"},
		{HTML: "<a href='http://www.google.com' data-hint='Hello'>Hello</a>", ExpectResult: "<a href=\"http://www.google.com\" rel=\"nofollow\">Hello</a>"},
	}

	unsafeRawTestCases := []rawTestCase{
		{HTML: "<a href='http://g.cn'>Hello</a>", ExpectResult: "<a href='http://g.cn'>Hello</a>"},
		{HTML: "<a href='#' data-hint='Hello'>Hello</a>", ExpectResult: "<a href='#' data-hint='Hello'>Hello</a>"},
	}

	context := Context{
		Admin: New(&qor.Config{}),
	}
	funcMaps := context.FuncMap()

	for i, testcase := range rawTestCases {
		result := funcMaps["raw"].((func(string) template.HTML))(testcase.HTML)
		var hasError bool
		if result != template.HTML(testcase.ExpectResult) {
			t.Error(color.RedString(fmt.Sprintf("Admin FuncMap raw #%v: expect get %v, but got '%v'", i+1, testcase.ExpectResult, result)))
			hasError = true
		}
		if !hasError {
			fmt.Print(color.GreenString(fmt.Sprintf("Admin FuncMap raw #%v: Success\n", i+1)))
		}
	}

	for i, testcase := range unsafeRawTestCases {
		result := funcMaps["unsafe_raw"].((func(string) template.HTML))(testcase.HTML)
		var hasError bool
		if result != template.HTML(testcase.ExpectResult) {
			t.Error(color.RedString(fmt.Sprintf("Admin FuncMap unsafe_raw #%v: expect get %v, but got '%v'", i+1, testcase.ExpectResult, result)))
			hasError = true
		}
		if !hasError {
			fmt.Print(color.GreenString(fmt.Sprintf("Admin FuncMap unsafe_raw #%v: Success\n", i+1)))
		}
	}
}

type FakeStruct struct {
	gorm.Model
	Name string
}

func TestIsEqual(t *testing.T) {
	c1 := FakeStruct{Name: "c1"}
	c1.ID = 1
	c2 := FakeStruct{Name: "c2"}
	c2.ID = 1

	context := Context{
		Admin: New(&qor.Config{}),
	}
	if !context.isEqual(c1, c2) {
		t.Error("same primary key is not equal")
	}

	c1.ID = 2
	if context.isEqual(c1, c2) {
		t.Error("different primary key is equal")
	}

	a := "a test"
	b := "another one"
	if context.isEqual(a, b) {
		t.Error("different string is equal")
	}

	c := 11
	d := 11
	if !context.isEqual(c, d) {
		t.Error("same int is not equal")
	}
}
