exec scriptmanager#DefineAndBind('s:c','g:vim_addon_sbt', '{}')
let s:c['mxmlc_default_args'] = get(s:c,'mxmlc_default_args', ['--strict=true'])

if !exists('g:sbt_debug')
  let g:sbt_debug = 0
endif

" author: Marc Weber <marco-oweber@gxm.de>

" usage example:
" ==============
" requires python!
" map <F2> :exec 'cfile '.sbt#Compile(["mxmlc", "-load-config+=build.xml", "-debug=true", "-incremental=true", "-benchmark=false"])<cr>

" implementation details:
" ========================
" python is used to run a sbt process reused.
" This code is copied and modified. source vim-addon-sbt
" Because Vim is not threadsafe ~compile commands are not supported.
" (There are workaround though)
" You can still use vim-addon-actions to make Vim trigger recompilation
" when you write a file


let s:self=expand('<sfile>:h')

" TODO implement shutdown, clean up ?
"      support quoting of arguments
fun! sbt#Compile(sbt_command_list)

  let g:sbt_command_list = a:sbt_command_list

  if !has('python')
    throw "python support required to run sbt process"
  endif

  " using external file which can be tested without Vim.
  exec 'pyfile '.s:self.'/sbt.py'

python << PYTHONEOF
f = sbtCompiler.sbt(vim.eval('g:sbt_command_list'))
vim.command("let g:sbt_result='%s'"%f)
PYTHONEOF

  " unlet g:sbt_command_list
  " unlet g:sbt_result
  return g:sbt_result
endf


fun! sbt#CompileRHS(usePython, args)
  " errorformat taken from http://code.google.com/p/simple-build-tool/wiki/IntegrationSupport
  let ef=
      \  '%E\ %#[error]\ %f:%l:\ %m,%C\ %#[error]\ %p^,%-C%.%#,%Z'
      \.',%W\ %#[warn]\ %f:%l:\ %m,%C\ %#[warn]\ %p^,%-C%.%#,%Z'
  "   \.',%-G%.%#'

  let args = a:args

  " let ef = escape(ef, '"\')
  if !a:usePython
    let args =  ["java", "-Dsbt.log.noformat=true", "-jar", SBT_JAR()] + args
  endif
  let args = actions#ConfirmArgs(args,'sbt command')
  if a:usePython
    let ef = escape(ef, '"\')
    return ['exec "set efm='.ef.'" ',"exec 'cfile '.sbt#Compile(".string(args).")"]
  else
    " use RunQF
    return "call bg#RunQF(".string(args).", 'c', ".string(ef).")"
  endif
endfun
