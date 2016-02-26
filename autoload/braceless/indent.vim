" Gets the indent level of a line and modifies it with a indent level delta.
function! braceless#indent#level(expr, delta)
  let indent_len = indent(a:expr)
  let d = 1
  if !&expandtab
    let indent_len = (indent_len / &ts) + a:delta
  else
    let indent_len += &sw * a:delta
    let d = &sw
  endif
  return max([0, indent_len]) / d
endfunction


" Gets the indent level (in characters) of a line and modifies it with a
" indent level delta.
function! braceless#indent#space(expr, delta)
  let indent_char = ' '
  let indent_len = indent(a:expr)
  if !&expandtab
    let indent_char = '\t'
    let indent_len = (indent_len / &ts) + a:delta
  else
    let indent_len += &sw * a:delta
  endif
  return [indent_char, max([0, indent_len])]
endfunction


" Indent
let s:handlers = {}
let s:str_skip = "synIDattr(synID(line('.'), col('.'), 1), 'name')"
                  \." =~? '\\%(Comment\\|Todo\\|String\\|DoctestValue\\|DocTest\\|DocTest2\\)$'"
let s:collection = ['(\|{\|\[', ')\|}\|\]']


function! braceless#indent#add_handler(filetype, handlers)
  let s:handlers[a:filetype] = a:handlers
endfunction


function! braceless#indent#non_block(line, prev)
  let handler = get(s:handlers, &l:filetype, {})
  " Try collection pairs
  let pos = getpos('.')
  if getline(a:line) =~ s:collection[1]
    keepjumps normal! ^
  endif
  let col_head = searchpairpos(s:collection[0], '', s:collection[1], 'nbW', s:str_skip)
  if col_head[0] != a:line && col_head[0] > 0
    let col_tail = searchpairpos(s:collection[0], '', s:collection[1], 'ncW', s:str_skip)
    if col_head[0] == col_tail[0]
      " All on the same line
      throw 'cont'
    endif

    " The pair start is at the end of the line, indent past the pair start
    " line.
    let indent_delta = 1

    try
      if has_key(handler, 'collection')
        call setpos('.', pos)
        return handler.collection(a:line, col_head, col_tail)
      else
        throw 'cont'
      endif
    catch /cont/
      " If the line doesn't end with a pair start, line up with it
      if getline(col_head[0]) !~ '\%('.s:collection[0].'\)\s*$'
        return col_head[1]
      endif

      " Different indentation if we're on the line with the tail
      if a:line == col_tail[0]
        if getline(col_tail[0]) =~ '^\s*\%('.s:collection[1].'\)\+\s*$'
          let indent_delta = 0
        endif
      endif
    endtry

    return braceless#indent#space(col_head[0], indent_delta)[1]
  endif
  call setpos('.', pos)

  " Try docstrings
  if braceless#is_string(a:prev) || getline(a:line) =~ '\%("""\|''''''\)'
    let docstr = braceless#docstring(a:line)
    try
      if has_key(handler, 'docstring')
        return handler.docstring(a:line, docstr)
      else
        throw 'cont'
      endif
    catch /cont/
      if docstr[0] != 0
        if a:line == docstr[0] || a:line == docstr[1]
          let pattern = braceless#get_pattern()
          let block = search('^\s*'.pattern.start, 'nbW')
          return braceless#indent#space(block, 1)[1]
        endif

        let prev = prevnonblank(a:line - 1)
        return braceless#indent#space(prev, 0)[1]
      endif
    endtry
  endif

  throw 'cont'
endfunction


function! s:handle_blocks(line, prev)
  let handler = get(s:handlers, &l:filetype, {})
  let block = braceless#get_block_lines(a:prev, 1)
  if block[2] == 0
    return -1
  endif

  try
    if has_key(handler, 'block')
      return handler.block(a:line, block)
    else
      throw 'cont'
    endif
  catch /cont/
    if a:line - a:prev > 2 && a:line > block[1]
      " Gone past the point of caring.  Use the user's indent.
      return -1
    elseif a:line == block[2] || a:line == block[3]
      " On a block head
      if prevnonblank(block[2] - 1) == 0
        " Special case for the first block in a file
        return 0
      endif
      let block2 = braceless#get_block_lines(prevnonblank(block[2] - 1), 1)
      let delta = 0
      if block2[1] >= block[1] || block2[2] == block2[1]
        " If the previous block contains this block.  If the previous block
        " doesn't have a body it will adopt this one.
        let delta = 1
      endif
      return braceless#indent#space(block2[2], delta)[1]
    elseif a:line > block[1] && a:line - a:prev > 1
      " Current line is past the end of a block, drop back one level
      return braceless#indent#space(block[2], 0)[1]
    elseif a:prev > block[1]
      " There is another line before end of the previous block, match its
      " indent.
      return braceless#indent#space(a:prev, 0)[1]
    endif

    return braceless#indent#space(block[2], 1)[1]
  endtry
endfunction


function! braceless#indent#expr(line)
  let prev = prevnonblank(a:line)

  try
    " This must return as-is
    return braceless#indent#non_block(a:line, prev)
  catch /cont/
  endtry

  let i = s:handle_blocks(a:line, prev)
  if i >= 0 && &expandtab
    " Fix the indent level so it's a multiple of &sw
    let i = &sw * (i / &sw)
  endif
  return i
endfunction
