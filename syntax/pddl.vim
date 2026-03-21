" syntax/pddl.vim
if exists("b:current_syntax")
  finish
endif

syntax case ignore

" ── Top-level structure ────────────────────────────────────────────────────────
syntax keyword pddlKeyword    define domain problem
syntax keyword pddlSection    contained
      \ :requirements :types :constants :predicates :functions
      \ :action :durative-action :derived :constraints
syntax keyword pddlSection    contained
      \ :domain :objects :init :goal :metric

" ── Action sub-keys ────────────────────────────────────────────────────────────
syntax keyword pddlActionKey  contained
      \ :parameters :precondition :effect
      \ :duration :condition

" ── Requirements ──────────────────────────────────────────────────────────────
syntax keyword pddlRequirement contained
      \ :strips :typing :negative-preconditions
      \ :disjunctive-preconditions :equality
      \ :existential-preconditions :universal-preconditions
      \ :quantified-preconditions :conditional-effects
      \ :fluents :numeric-fluents :object-fluents :adl
      \ :durative-actions :duration-inequalities
      \ :continuous-effects :derived-predicates
      \ :timed-initial-literals :preferences
      \ :constraints :action-costs

" ── Logical operators ─────────────────────────────────────────────────────────
syntax keyword pddlLogical    and or not imply forall exists when

" ── Temporal operators ────────────────────────────────────────────────────────
syntax keyword pddlTemporal   at start at end over all

" ── Numeric operators ─────────────────────────────────────────────────────────
syntax keyword pddlNumeric    increase decrease assign scale-up scale-down

" ── Metric keywords ───────────────────────────────────────────────────────────
syntax keyword pddlMetric     minimize maximize total-time total-cost

" ── Variables ─────────────────────────────────────────────────────────────────
syntax match  pddlVariable    /?\w\+/

" ── Type annotation ───────────────────────────────────────────────────────────
syntax match  pddlTypeOf      /-\s*\w\+/

" ── Comments ──────────────────────────────────────────────────────────────────
syntax match  pddlComment     /;.*/

" ── Numbers ───────────────────────────────────────────────────────────────────
syntax match  pddlNumber      /\<\d\+\(\.\d*\)\?\>/

" ── Parentheses ───────────────────────────────────────────────────────────────
syntax match  pddlParen       /[()]/

" ── Plan actions (blocksworld & common) ──────────────────────────────────────
" STACK / UNSTACK: two shades of blue
syntax keyword pddlPlanStack   stack
syntax keyword pddlPlanUnstack unstack

" PICK-UP / PUT-DOWN: two shades of amber
syntax keyword pddlPlanPickup  pick-up
syntax keyword pddlPlanPutdown put-down

" ── Colon-prefixed keywords (:action :parameters etc.) ───────────────────────
syntax match  pddlColon        /:\w\+[-\w]*/

" ── International / non-ASCII characters (lint as error) ─────────────────────
syntax match  pddlIntlError    /\S*[^\x00-\x7F]\S*/

" ── Highlight links ───────────────────────────────────────────────────────────
highlight default link pddlKeyword     Keyword
highlight default link pddlSection     Structure
highlight default link pddlActionKey   Label
highlight default link pddlRequirement Special
highlight default link pddlLogical     Conditional
highlight default link pddlTemporal    Type
highlight default link pddlNumeric     Function
highlight default link pddlMetric      Statement
highlight default link pddlVariable    Identifier
highlight default link pddlTypeOf      Type
highlight default link pddlComment     Comment
highlight default link pddlNumber      Number
highlight default link pddlParen       Delimiter
highlight default pddlIntlError guisp=#FF0000 gui=undercurl cterm=underline ctermfg=196

" STACK (bright blue) / UNSTACK (steel blue)
highlight default pddlPlanStack   guifg=#89DDFF ctermfg=117
highlight default pddlPlanUnstack guifg=#61AFEF ctermfg=75

" PICK-UP (light amber) / PUT-DOWN (deep amber)
highlight default pddlPlanPickup  guifg=#FFCB6B ctermfg=222
highlight default pddlPlanPutdown guifg=#C78D3A ctermfg=172

" :word (violet — distinct from white)
highlight default pddlColon       guifg=#C678DD ctermfg=176

let b:current_syntax = "pddl"
