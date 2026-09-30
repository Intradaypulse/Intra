import com.pdfmateapp.pdfmate.CancellableOutputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.Arrays;
import java.util.concurrent.atomic.AtomicBoolean;

public class CancellableOutputStreamTest {
    public static void main(String[] args) throws Exception {
        AtomicBoolean cancelled = new AtomicBoolean();
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] input = new byte[100000];
        Arrays.fill(input, (byte) 42);
        try (CancellableOutputStream stream = new CancellableOutputStream(output, cancelled)) {
            stream.write(input);
            stream.flush();
        }
        if (!Arrays.equals(input, output.toByteArray())) throw new AssertionError("Corrupt output");
        final boolean[] closed = {false};
        ByteArrayOutputStream interrupted = new ByteArrayOutputStream() {
            @Override public void write(byte[] b, int offset, int length) {
                super.write(b, offset, length);
                cancelled.set(true);
            }
            @Override public void close() { closed[0] = true; }
        };
        try (CancellableOutputStream stream = new CancellableOutputStream(interrupted, cancelled)) {
            stream.write(input);
            throw new AssertionError("Cancellation ignored");
        } catch (IOException expected) {
            if (!expected.getMessage().contains("cancelled")) throw expected;
        }
        if (interrupted.size() != 16 * 1024) throw new AssertionError("Save did not stop at next chunk");
        if (!closed[0]) throw new AssertionError("Descriptor not closed");
        ByteArrayOutputStream beforeStart = new ByteArrayOutputStream();
        try (CancellableOutputStream stream = new CancellableOutputStream(beforeStart, cancelled)) {
            stream.write(1);
            throw new AssertionError("Pre-cancel ignored");
        } catch (IOException expected) { }
        if (beforeStart.size() != 0) throw new AssertionError("Wrote after cancel");
        System.out.println("Native cancellation tests passed");
    }
}
