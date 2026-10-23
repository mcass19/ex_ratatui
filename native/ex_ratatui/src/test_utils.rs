#[cfg(test)]
pub mod helpers {
    use ratatui::backend::TestBackend;
    use ratatui::Terminal;

    /// Read a single line from the test backend buffer, trimming trailing whitespace.
    pub fn buffer_line(terminal: &Terminal<TestBackend>, y: u16, width: u16) -> String {
        let buf = terminal.backend().buffer();
        (0..width)
            .map(|x| buf.cell((x, y)).map_or(" ", |c| c.symbol()).to_string())
            .collect::<String>()
            .trim_end()
            .to_string()
    }

    /// Concatenate every row of the buffer into a single newline-separated string.
    /// Convenient for assertions that don't care where on screen the text lands.
    pub fn buffer_to_string(terminal: &Terminal<TestBackend>) -> String {
        let buf = terminal.backend().buffer();
        let area = buf.area;
        (0..area.height)
            .map(|y| buffer_line(terminal, y, area.width))
            .collect::<Vec<_>>()
            .join("\n")
    }
}

/// Since rustler 0.39 the `enif_*` NIF API is linked directly on Linux
/// instead of through a table filled in when the BEAM loads the NIF. The
/// cdylib is fine (beam.smp provides the symbols at load), but a `cargo test`
/// binary has no BEAM to resolve them against and fails to link. The unit
/// tests never call into the NIF API, so the test binary gets stubs that only
/// satisfy the linker and abort if anything does call them. A link error
/// naming another `enif_*` symbol means new code reaches it: add it here.
#[cfg(all(test, target_os = "linux"))]
mod nif_api_stubs {
    macro_rules! stubs {
        ($($name:ident),* $(,)?) => {
            $(
                #[no_mangle]
                extern "C" fn $name() -> ! {
                    panic!(concat!(stringify!($name), " called outside the BEAM"))
                }
            )*
        };
    }

    stubs!(
        enif_alloc_binary,
        enif_alloc_env,
        enif_alloc_resource,
        enif_free_env,
        enif_get_double,
        enif_get_int,
        enif_get_list_cell,
        enif_get_long,
        enif_get_map_size,
        enif_get_map_value,
        enif_get_resource,
        enif_get_tuple,
        enif_get_uint,
        enif_get_ulong,
        enif_inspect_binary,
        enif_is_atom,
        enif_is_empty_list,
        enif_is_exception,
        enif_is_identical,
        enif_is_list,
        enif_is_map,
        enif_keep_resource,
        enif_make_atom_len,
        enif_make_badarg,
        enif_make_binary,
        enif_make_copy,
        enif_make_list_from_array,
        enif_make_map_from_arrays,
        enif_make_map_put,
        enif_make_new_binary,
        enif_make_new_map,
        enif_make_resource,
        enif_make_tuple_from_array,
        enif_make_uint,
        enif_make_ulong,
        enif_map_iterator_create,
        enif_map_iterator_destroy,
        enif_map_iterator_get_pair,
        enif_map_iterator_next,
        enif_map_iterator_prev,
        enif_raise_exception,
        enif_release_binary,
        enif_release_resource,
        enif_schedule_nif,
        enif_snprintf,
    );
}
