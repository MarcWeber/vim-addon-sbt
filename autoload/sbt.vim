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


function! sbt#SBTCommandCompletion(ArgLead, CmdLine, CursorPos)
  let list = split(join(readfile(sbt#Compile(["\t"]),'b'),"\n"),'\W\+')
  return filter(list,'v:val =~ '.string(a:ArgLead))
endf

" TODO implement shutdown, clean up ?
"      support quoting of arguments
fun! sbt#Compile(sbt_command_list)

  let g:sbt_command_list = a:sbt_command_list

  if !has('python')
    throw "python support required to run sbt process"
  endif

  " using external file which can be tested without Vim.
  exec 'pyfile '.s:self.'/sbt.py'


  silent! unlet g:sbt_result

python << PYTHONEOF
if sbtCompiler.startUpError != "":
  vim.command("let g:sbt_result="+vimQuote(sbtCompiler.startUpError))
  sbtCompiler.startUpError = ""
else:
  f = sbtCompiler.sbt(vim.eval('g:sbt_command_list'))
  vim.command("let g:sbt_result="+vimQuote(f))
PYTHONEOF

  " unlet g:sbt_command_list
  return g:sbt_result
endf

let s:ef = 
      \  '%+G==!>%.%#'
      \.',%E\ %#[error]\ %f:%l:\ %m,%C\ %#[error]\ %p^,%-C%.%#,%Z'
      \.',%W\ %#[warn]\ %f:%l:\ %m,%C\ %#[warn]\ %p^,%-C%.%#,%Z'
      \.',%-G\[info\]%.%#'

" no arg? just send "" (enter)
fun! sbt#RunCommand(...)
  let cmd = a:0 > 0 ? a:1 : [""]
  exec "set efm=".s:ef
  exec 'cfile '.sbt#Compile(cmd)
endf

fun! sbt#CompileRHS(usePython, args)
  " errorformat taken from http://code.google.com/p/simple-build-tool/wiki/IntegrationSupport
  let ef= s:ef

  let args = a:args

  " let ef = escape(ef, '"\')
  if !a:usePython
    let args =  ["java", "-Dsbt.log.noformat=true", "-jar", SBT_JAR()] + args
  endif
  let args = actions#ConfirmArgs(args,'sbt command')
  if a:usePython
    return 'call sbt#RunCommand('.string(args).')'
  else
    " use RunQF
    return "call bg#RunQF(".string(args).", 'c', ".string(ef).")"
  endif
endfun

" add feature {{{1

" type is either build or plugins
fun! sbt#PathOf(type, create) abort
  let key = a:type.'filepath'
  if !has_key(s:c, key) || !filereadable(s:c[key])
    let g = 'project/'.a:type.'/*.scala'
    let files = split(glob(g),"\n")
    let s:c[key] = tlib#input#List("s","select local name", files)
  endif
  let f = s:c[key] 
  if !filereadable(f)
    if a:create
      let templates = {}
      let templates['build'] = {}
      let templates['plugins'] = {}

      let templates['build']['basename'] = 'SbtProject.scala'
      let templates['build']['content'] =
            \    ['import sbt._'
            \    ,'class SbtProject(info: ProjectInfo) extends DefaultProject(info)'
            \    ,'{'
            \    ,'}']

      let templates['plugins']['basename'] = 'Plugins.scala'
      let templates['plugins']['content'] =
            \    ['import sbt._'
            \    ,'class Plugins(info: ProjectInfo) extends PluginDefinition(info) {'
            \    ,'}']

      let t = templates[a:type]
      let p = 'project/'.a:type
      let f = p.'/'.t['basename']
      call mkdir(p, 'p')
      call writefile(t['content'],f)
    else
      throw "no ".g." file found"
    endif
  endif
  return f
endf

" imports: ['import foo.bar']
fun! sbt#AddImports(imports)
  for i in a:imports
    " TODO escape, break if import exists
    if search(i) | break | endif
    normal G
    if !search('\<import\>','b')
      normal gg
    endif
    put=i
  endfor
endf

fun! sbt#ListRTPFiles(path, name, ext)
  let matches = []
  for r in split(&runtimepath,',')
    let matches += split(glob(r.'/'.a:path.'/'.a:name.a:ext),"\n")
  endfor
  return matches
endf

fun! sbt#FeatureDict(name)
  return sbt#ParseInfoFile(
    \ tlib#input#List("s","select dict", sbt#ListRTPFiles('sbt-extensions',a:name,'.txt')))
endf

fun! sbt#AddFeature(...) abort
  for key in a:000
    let feature = sbt#FeatureDict(key)
    for type in ['plugins','build']
      let key_names = map(['_imports','_with','_code'],string(type).'.v:val')
      let [ki,kw,kc] = key_names
      let [di,dw,dc] = map(key_names,'has_key(feature,v:val)')
      if di || dw || dc
        let f = sbt#PathOf(type, 1)
        
        exec (strlen(bufname(f)) > 0 ? 'b ' : 'sp ').f
        " add imports
        if di | call sbt#AddImports(feature[ki]) | endif

        " add with traits
        if dw 
          normal gg
          " ^class to find the top level class only
          if !search('^class') || !search('{')
            echoe "no class found. Can't add with"
          else
            if col('.') > 1
              " put { into new line:
              s/ {$/{/e
              exec "normal $i\<cr>"
            endif
            normal k
            " add "with XX" before opening { as new line if it doesn't exist
            " yet
            for w in feature[kw]
              if search(w,'n') | break | endif
              put='    '.w
            endfor
          endif
        endif

        " add extra code
        if dc 
          if !search('class') || !search('{')
            echoe "no class found. Can't add with"
          else
            " jump to closing }
            normal %k
            for l in feature[kc]
              put=repeat(' ',&sw).l
            endfor
          endif
        endif
      endif
    endfor
  endfor
endf

function! sbt#AddFeatureCmdCompletion(ArgLead, CmdLine, CursorPos)
  return filter(map(sbt#ListRTPFiles('sbt-extensions','*','.txt'),'fnamemodify(v:val,":t")[:-5]'),'v:val =~ '.string(a:ArgLead))
endf
" }}}



" parse config file which looks like this:
" ==key:
" \line1
" \line2
"
" ==key2:
" \line1
" \line2
"
" only lines which are prefixed by \ are concatenated. This is for readability
fun! sbt#ParseInfoFile(file)
  let lines = readfile(a:file,'b')
  let last_key = ''
  let conc = []
  let d = {}
  let regex='^==\zs[^ ]*\ze:'
  for l in lines
    if l =~ regex
      if last_key != ''
        let d[last_key] = conc
        let conc = []
      endif
      let last_key = matchstr(l, regex)
    else
      if l =~ '^\' | call add(conc,l[1:]) | endif
    endif
  endfor
  if last_key != ''
    let d[last_key] = conc
  endif
  return d
endf

" if first arg is a readable file use that else use lines from currentn buffer
" additional args are ignore patterns used to drop matches. Example:
" sbt#ScalaExceptionTraceToQuickFix('err.txt','\/src\/','\/src_managed\/')
fun! sbt#ScalaExceptionTraceToQuickFix(...)
  let list = copy(a:000)
  if len(list) > 0 && filereadable(list[0])
    let maybe_file = list[0]
    let list = list[1:]
  else
    let maybe_file = ""
  endif

  " remaining args = ignore patterns
  let ignore_patterns = list

  let lines = (maybe_file == "")
    \ ? getline(1,line('$'))
    \ : readfile(maybe_file)
  if (!exists('g:scala_source_dirs'))
    let g:scala_source_dirs = []
  endif
  let scala_source_dirs = ['.']+ g:scala_source_dirs

  let map = {}
  let g:map = map

  " build up map cache
  for d in scala_source_dirs
    for f in split(glob(d.'/**/*.scala'),"\n")
      let base = fnamemodify(f,':t')
      if !has_key(map, base) | let map[base] = [] | endif
      call add(map[base], f)
    endfor
  endfor

  let error_list = []
  for l in lines
    let m = matchlist(l, 'at \([^(]\+\)(\([^:)]\+\):\(\d\+\))')
    if m == []
      call add(error_list, {'text' : l} )
    else
      let files = get(map,m[2],[])
      if ignore_patterns != []
        call filter(files,'v:val !~ '.string(join(ignore_patterns,'\|')))
      endif
      if files == []
        call add(error_list, {'text' : l} )
      else
        let nr = 1
        for f in files
          call add(error_list,
              \ { 'text' : m[1]." nr ".nr, 'lnum' : m[3], 'filename': f } )
          let nr = nr +1
        endfor
      endif
    endif
  endfor

  call setqflist(error_list)
endfun

" vim: fdm=marker
