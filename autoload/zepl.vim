" =====================================================
" Description:  Simple REPL in Vim.
" File:         autoload/zepl.vim
" =====================================================

let s:repl_bufnr = 0

let s:newline = has('unix') ? "\n" : "\r\n"

function! s:error(msg) abort
    echohl ErrorMsg
    echo a:msg
    echohl NONE
endfunction

function! zepl#start(cmd, mods, size) abort
    if a:cmd !=# ''
        if s:repl_bufnr
            call s:error('REPL already running')
            return
        endif
        let cmd = a:cmd
    elseif exists('b:repl_config') && has_key(b:repl_config, 'cmd')
        let cmd = b:repl_config['cmd']
    elseif !s:repl_bufnr
        call s:error('No command specified')
        return
    endif

    if !s:repl_bufnr
        let name = printf('zepl: %s', cmd)

        if has('nvim')
            " XXX: Hacky code to make Neovim's terminal to behave like Vim's.
            set hidden
            split | enew
            call termopen(cmd, {'on_exit': function('<SID>repl_closed')})
            exec 'file ' . name | let b:term_title = name
            let s:repl_bufnr = bufnr('%')
            quit
        else
            let s:repl_bufnr = term_start(cmd, {
                        \ 'term_name': name,
                        \ 'term_finish': 'close',
                        \ 'close_cb': function('<SID>repl_closed'),
                        \ 'hidden': 1
                        \ })
        endif
    endif

    call zepl#jump(a:mods, a:size)
endfunction

function! s:repl_closed(...) abort
    let s:repl_bufnr = 0
endfunction

function! zepl#jump(mods, size) abort
    if !s:repl_bufnr
        call s:error('No active REPL')
        return
    endif

    for mod in expand(a:mods, 0, 1)
        if mod ==# 'hide'
            return
        endif
    endfor

    let swb = &switchbuf
    set switchbuf+=useopen

    execute a:mods . ' sbuffer ' . s:repl_bufnr

    if a:size
        execute a:mods . ' resize ' . a:size
    endif

    if has('nvim')
        startinsert
    endif

    let &switchbuf = swb
endfunction

" zepl#send({text} [, {verbatim}])
function! zepl#send(text, ...) abort
    if !s:repl_bufnr
        call s:error('No active REPL')
        return
    endif

    let text = a:text
    let verbatim = get(a:, 1, 0)

    if type(text) == v:t_list
        if !verbatim
            " Add missing newlines.
            call map(text, {_, val -> val ==# '\n$' ? val : val . s:newline})
            " Remove trailing and leading white space.
            let text = split(trim(join(text, '')) . s:newline, '\n\zs', 1)
        endif
    else
        if !verbatim
            let text = trim(text) . s:newline
        endif

        let text = split(text, '\n\zs', 1)
    endif

    if has('nvim')
        call chansend(getbufvar(s:repl_bufnr, '&channel'), text)
    else
        for l in text
            call term_sendkeys(s:repl_bufnr, l)
            call term_wait(s:repl_bufnr)
        endfor
    endif
endfunction

function! s:get_text(start, end, mode) abort
    let [b, start_line, start_col, o] = getpos(a:start)
    let [b, end_line, end_col, o] = getpos(a:end)

    " Correct column indexes
    if a:mode ==# 'V' || a:mode ==# 'line'
        let [start_col, end_col] = [0, -1]
    else
        let [start_col, end_col] = [start_col - 1, end_col - 1]
    endif

    let lines = getline(start_line, end_line)
    let lines[-1] = lines[-1][:end_col]
    let lines[0] = lines[0][start_col:]

    return lines
endfunction

function! zepl#send_region(type, ...) abort
    let sel_save = &selection
    let &selection = 'inclusive'

    if a:0  " Visual mode
        let lines = s:get_text("'<", "'>", visualmode())
    else
        let lines = s:get_text("'[", "']", a:type)
    endif

    call zepl#send(lines)

    let &selection = sel_save
endfunction