package com.paply.android;

import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.os.Bundle;
import android.text.InputType;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import android.view.inputmethod.InputConnectionWrapper;
import android.widget.*;

/** Separate-process editor; Java deliberately needs no target-APK Kotlin runtime. */
public class ImeFixtureActivity extends Activity {
    private LinearLayout body;
    @Override public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(24, 80, 24, 0);
        TextView title = new TextView(this);
        title.setText("Paply · IME-Abnahme (Test-APK)"); title.setTextSize(20);
        body.addView(title);
        EditText first = field(com.paply.android.test.R.id.button_fixture_first, "Erstes Textfeld", InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE, false);
        if (getIntent().getBooleanExtra("emptyWithoutHint", false)) first.setHint(null);
        field(com.paply.android.test.R.id.button_fixture_second, "Zweites Textfeld", InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE, false);
        field(com.paply.android.test.R.id.button_fixture_password, "Passwort", InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD, false);
        field(com.paply.android.test.R.id.button_fixture_reject, "Editor lehnt Einsetzen ab", InputType.TYPE_CLASS_TEXT, true);
        TextView clipboard = new TextView(this); clipboard.setTextSize(16);
        Button check = new Button(this); check.setText("Zwischenablage prüfen");
        check.setOnClickListener(v -> {
            ClipData clip = getSystemService(ClipboardManager.class).getPrimaryClip();
            clipboard.setText(clip == null ? "Leer" : clip.getItemAt(0).getText());
        });
        Button seed = new Button(this); seed.setText("Zwischenablage vorbelegen");
        seed.setOnClickListener(v -> getSystemService(ClipboardManager.class).setPrimaryClip(ClipData.newPlainText("Test", "Vorheriger Clip")));
        body.addView(seed);
        body.addView(check); body.addView(clipboard); setContentView(body);
        if (savedInstanceState == null) first.requestFocus();
    }
    private EditText field(int id, String label, int type, boolean reject) {
        EditText edit = new EditText(this) {
            @Override public boolean performAccessibilityAction(int action, Bundle arguments) {
                if (reject && action == android.view.accessibility.AccessibilityNodeInfo.ACTION_SET_TEXT) return false;
                return super.performAccessibilityAction(action, arguments);
            }
            @Override public boolean onTextContextMenuItem(int id) {
                if (reject && id == android.R.id.paste) return false;
                return super.onTextContextMenuItem(id);
            }
            @Override public InputConnection onCreateInputConnection(EditorInfo info) {
                InputConnection connection = super.onCreateInputConnection(info);
                if (!reject || connection == null) return connection;
                return new InputConnectionWrapper(connection, false) {
                    @Override public boolean commitText(CharSequence text, int position) { return false; }
                };
            }
        };
        edit.setId(id); edit.setContentDescription(label); edit.setHint(label); edit.setInputType(type); edit.setTextSize(16);
        edit.setMinLines(1); edit.setMaxLines(3);
        body.addView(edit, new LinearLayout.LayoutParams(-1, -2));
        return edit;
    }
}
