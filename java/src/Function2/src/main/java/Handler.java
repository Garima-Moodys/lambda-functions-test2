import java.util.HashMap;
import com.google.gson.Gson;

public class Handler {
    public Object handler(Object event) {
        Gson gson = new Gson();
        System.out.println("hello garima");

        return new HashMap();
    }
}
