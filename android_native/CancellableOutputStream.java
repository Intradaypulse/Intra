package com.pdfmateapp.pdfmate;

import java.io.IOException;
import java.io.OutputStream;
import java.util.concurrent.atomic.AtomicBoolean;

/** Interrupts PDFBox's incremental copy at bounded output-write checkpoints. */
public final class CancellableOutputStream extends OutputStream {
    private static final int CHUNK_SIZE = 16 * 1024;
    private final OutputStream destination;
    private final AtomicBoolean cancelled;

    public CancellableOutputStream(OutputStream destination, AtomicBoolean cancelled) {
        this.destination = destination;
        this.cancelled = cancelled;
    }

    private void check() throws IOException {
        if (cancelled.get()) throw new IOException("OCR cancelled during save");
    }

    @Override public void write(int value) throws IOException {
        check();
        destination.write(value);
    }

    @Override public void write(byte[] bytes, int offset, int length) throws IOException {
        if (offset < 0 || length < 0 || offset > bytes.length - length) {
            throw new IndexOutOfBoundsException();
        }
        while (length > 0) {
            check();
            int count = Math.min(CHUNK_SIZE, length);
            destination.write(bytes, offset, count);
            offset += count;
            length -= count;
        }
        check();
    }

    @Override public void flush() throws IOException {
        check();
        destination.flush();
    }

    @Override public void close() throws IOException {
        // Always release the underlying descriptor, including after cancellation.
        destination.close();
    }
}
