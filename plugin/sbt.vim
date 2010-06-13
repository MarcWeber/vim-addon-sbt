" sbt-launch-*.jar location
if !exists('*SBT_JAR')
  fun! SBT_JAR()
    " assume that if sbt exists that it is a script which contains the .jar
    " location (linux only!)
    if executable('sbt')
      let script = system('which sbt')
      let lines = readfile(substitute(script,'[\r\n]','','g'))
      if lines[0] =~ '^#!'
        return  matchstr(join(lines,"\n"), '\zs[^ \t\r\n]*sbt-launch[^ \t\r\n]*.jar\>\ze')
      endif
    endif
    echoe "Can't find sbt-launch-*.jar. Please define SBT_JAR in your ~/.vimrc. It should return the jar location"
  endf
endif

if !exists('g:sbt')
  " assume that this executable exists
  let g:sbt = "sbt"
endif

" TODO
call actions#AddAction('run sbt with bg process (requires python)', {'action': funcref#Function('sbt#CompileRHS',{'args':[1,["compile"]]})})
call actions#AddAction('run sbt with bg#RunQF'                    , {'action': funcref#Function('sbt#CompileRHS',{'args':[0,["compile"]]})})
