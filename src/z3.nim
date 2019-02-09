
## Almost all Z3 C API functions take a Z3_context argument. This Nim binding
## uses a block level template called `z3` which creates a Z3_context and injects
## this into the template scope. All other Z3 functions are implemented using
## templates who use this implicitly available context variable.
##
## For almost all Z3 operations that operate on `Z3_ast` nodes templates are
## available that convert native Nim types to `Z3_ast` where appropriate. This allows
## for easy integration with Nim variables and constants.
##
## Example code:
##
## .. code-block::nim
##
##   z3:
##     let x = Int("x")
##     let y = Int("y")
##     let z = Int("z")
##     let s = Solver()
##     s.assert 3 * x + 2 * y - z == 1
##     s.assert 2 * x - 2 * y + 4 * z == -2
##     s.assert x * -1 + y / 2 - z == 0
##     s.check_model:
##       echo model
##
## More examples are available in the nimble tests at https://github.com/zevv/nimz3/blob/master/tests/test1.nim
##
## For more info on Z3 check the official guide at https://rise4fun.com/z3/tutorialcontent/guide

import z3/z3_api
import strutils

export Z3_ast


type
  Z3Exception* = object of Exception
    ## Exception thrown from the Z3 error handler. The exception message is
    ## generated by the Z3 library and states the reason for the error


# Z3 type constructors

template mk_var(name: string, ty: Z3_sort): Z3_ast =
  let sym = Z3_mk_string_symbol(ctx, name)
  Z3_mk_const(ctx, sym, ty)

template Bool*(name: string): Z3_ast =
  ## Create a Z3 constant of the type Bool. `(declare-const a Bool)`
  mk_var(name, Z3_mk_bool_sort(ctx))

template Int*(name: string): Z3_ast =
  ## Create a Z3 constant of the type Int. `(declare-const a Int)`
  mk_var(name, Z3_mk_int_sort(ctx))

template Float*(name: string): Z3_ast =
  ## Create a Z3 constant of the type Float. `(declare-const a Float)`
  mkvar(name, Z3_mk_fpa_sort_double(ctx))


# Convert Z3_AST to Nim type after model check

template toBool*(v: Z3_ast): bool =
  ## Convert the (solved) Z3_ast node to a Nim bool
  var r: Z3_ast
  if Z3_eval(ctx, model, v, addr r):
    parseBool $r
  else:
    raise newException(Z3Exception, "Can not convert to int")

template toInt*(v: Z3_ast): int =
  ## Convert the (solved) Z3_ast node to a Nim int
  var r: Z3_ast
  if Z3_eval(ctx, model, v, addr r):
    parseInt $r
  else:
    raise newException(Z3Exception, "Can not convert to int")


# Stringifications

template `$`*(v: Z3_ast): string =
  ## Create a string representation of the Z3 ast node
  $Z3_ast_to_string(ctx, v)

template `$`*(m: Z3_model): string =
  ## Create a string representation of the Z3 model
  $Z3_model_to_string(ctx, m)

template `$`*(m: Z3_solver): string =
  ## Create a string representation of the Z3 solver
  $Z3_solver_to_string(ctx, m)



# Misc

template simplify*(s: Z3_ast): Z3_ast =
  Z3_simplify(ctx, s)


# Solver interface

template Solver*(): Z3_solver =
  ## Create a Z3 solver context
  Z3_mk_solver(ctx)

template assert*(s: Z3_solver, e: Z3_ast) =
  ## Assert hard constraint to the solver context.
  Z3_solver_assert(ctx, s, e)

template check*(s: Z3_solver): Z3_lbool =
  ## Check whether the assertions in a given solver are consistent or not.
  Z3_solver_check(ctx, s)

template get_model*(s: Z3_Solver): Z3_model =
  ## Retrieve the model for the last solver.check
  Z3_solver_get_model(ctx, s)

template push*(s: Z3_Solver, code: untyped) =
  ## Create a backtracking point. This is to be used as a block scope template,
  ## so the state pop will by automatically generated when leaving the scope:
  ##
  ## .. code-block::nim
  ##   z3:
  ##     let s = Solver()
  ##     s.assert ...
  ##     s.push:
  ##       s.assert ..
  ##       s.check
  ##     s.assert ...
  ##
  Z3_solver_push(ctx, s)
  block:
    code
  Z3_solver_pop(ctx, s, 1)

template check_model*(s: Z3_solver, code: untyped) =
  ## A helper block-scope template that combines `check` and `get_model`. If
  ## the solver was consistent the model is available in the variable `model`
  ## inside the block scope. If the solver failed a Z3Exception will be thrown.
  if Z3_solver_check(ctx, s) == Z3_L_TRUE:
    let model {.inject.} = Z3_solver_get_model(ctx, s)
    code
  else:
    raise newException(Z3Exception, "UNSAT")


# Optimizer interface

template Optimizer*(): Z3_optimize =
  ## Create a Z3 optimizer
  Z3_mk_optimize(ctx)

template minimize*(o: Z3_optimize, e: Z3_ast) =
  ## Add a minimization constraint.
  echo Z3_optimize_minimize(ctx, o, e)

template maximize*(o: Z3_optimize, e: Z3_ast) =
  ## Add a maximization constraint.
  echo Z3_optimize_maximize(ctx, o, e)

template assert*(o: Z3_optimize, e: Z3_ast) =
  ## Assert hard constraint to the optimization context.
  Z3_optimize_assert(ctx, o, e)


template eval*(v: Z3_ast): string =
  var r: Z3_ast
  if Z3_eval(ctx, model, v, addr r):
    $r
  else:
    ""

proc on_err(ctx: Z3_context, e: Z3_error_code) {.nimcall.} =
  let msg = $Z3_get_error_msg_ex(ctx, e)
  raise newException(Z3Exception, msg)


template z3*(code: untyped) =

  ## The main Z3 context template. This template creates an implicit
  ## Z3_context which all other API functions need. Z3 errors are
  ## caught and throw a Z3Exception

  block:

    let cfg = Z3_mk_config()
    Z3_set_param_value(cfg, "model", "true");
    let ctx {.inject.} = Z3_mk_context(cfg)
    Z3_del_config(cfg)
    Z3_set_error_handler(ctx, on_err)
    let fpa_rm {.inject.} = Z3_mk_fpa_round_nearest_ties_to_even(ctx)

    block:
      code


# Helper templates to generate multiple operators accepting (Z3_ast, Z3_ast),
# (T, Z3_ast) or (Z3_ast, T). This allows for easy mixing with native Nim types

# Nim -> Z3 type converters

proc to_z3(ctx: Z3_context, v: bool): Z3_ast =
  if v: Z3_mk_true(ctx) else: Z3_mk_false(ctx)

proc to_z3(ctx: Z3_context, v: int): Z3_ast =
  Z3_mk_int(ctx, v.cint,  Z3_mk_int_sort(ctx))

proc to_z3(ctx: Z3_context, v: float): Z3_ast =
  Z3_mk_fpa_numeral_double(ctx, v.cdouble, Z3_mk_fpa_sort(ctx, 11, 53))

proc vararg_helper[T](ctx: Z3_context, fn: T, vs: varargs[Z3_ast]): Z3_ast =
  fn(ctx, vs.len.cuint, unsafeAddr(vs[0]))

template unop(T: type, name: untyped, fn: untyped) =
  # Uni operation
  template name*(v: Z3_ast): Z3_ast = fn(ctx, v)
  #template name*(v: T): Z3_ast = fn(ctx, to_z3(ctx, v))

template binop(T: type, name: untyped, fn: untyped) =
  # Binary operation
  template name*(v1: Z3_ast, v2: Z3_ast): Z3_ast = fn(ctx, v1, v2)
  template name*(v1: Z3_ast, v2: T): Z3_ast = fn(ctx, v1, to_z3(ctx, v2))
  template name*(v1: T, v2: Z3_ast): Z3_ast = fn(ctx, to_z3(ctx, v1), v2)

template binop_rm(T: type, name: untyped, fn: untyped) =
  # Binary operation with rounding mode
  template name*(v1: Z3_ast, v2: Z3_ast): Z3_ast = fn(ctx, fpa_rm, v1, v2)
  template name*(v1: Z3_ast, v2: T): Z3_ast = fn(ctx, fpa_rm,v1, to_z3(ctx, v2))
  template name*(v1: T, v2: Z3_ast): Z3_ast = fn(ctx, fpa_rm, to_z3(ctx, v1), v2)

template varop(T: type, name: untyped, fn: untyped) =
  # Varargs operation, reduced to binary operation
  template name*(v1: Z3_ast, v2: Z3_ast): Z3_ast = vararg_helper(ctx, fn, v1, v2)
  template name*(v1: Z3_ast, v2: T): Z3_ast = vararg_helper(ctx, fn, v1, to_z3[T](ctx, v2))
  template name*(v1: T, v2: Z3_ast): Z3_ast = vararg_helper(ctx, fn, to_z3(ctx, v1), v2)


# Boolean operations

unop(bool, `not`, Z3_mk_not)
binop(bool, `==`, Z3_mk_eq)
binop(bool, `xor`, Z3_mk_xor)
varop(bool, `or`, Z3_mk_or)
varop(bool, `and`, Z3_mk_and)

# Integer operations

unop(int, `-`, Z3_mk_unary_minus)
binop(int, `<`, Z3_mk_lt)
binop(int, `>`, Z3_mk_gt)
binop(int, `<=`, Z3_mk_le)
binop(int, `>=`, Z3_mk_ge)
binop(int, `/`, Z3_mk_div)
binop(int, `mod`, Z3_mk_mod)
binop(int, `==`, Z3_mk_eq)
binop(int, `<->`, Z3_mk_iff)
varop(int, `+`, Z3_mk_add)
varop(int, `-`, Z3_mk_sub)
varop(int, `*`, Z3_mk_mul)
varop(int, `and`, Z3_mk_and)
varop(int, `or`, Z3_mk_or)

# Floating point operations (experimental)

binop(float, `<`, Z3_mk_fpa_lt)
binop(float, `>`, Z3_mk_fpa_gt)
binop(float, `<=`, Z3_mk_fpa_leq)
binop(float, `>=`, Z3_mk_fpa_geq)
binop(float, `==`, Z3_mk_fpa_eq)
binop(float, max, Z3_mk_fpa_max)
binop(float, min, Z3_mk_fpa_min)
binop_rm(float, `*`, Z3_mk_fpa_mul)
binop_rm(float, `/`, Z3_mk_fpa_div)
binop_rm(float, `+`, Z3_mk_fpa_add)
binop_rm(float, `-`, Z3_mk_fpa_sub)

# Generic operations

template distinc*(vs: varargs[Z3_ast]): Z3_ast = vararg_helper(ctx, Z3_mk_distinct, vs)


# vim: ft=nim

