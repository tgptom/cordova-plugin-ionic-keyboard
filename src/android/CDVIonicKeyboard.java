package io.ionic.keyboard;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaInterface;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CordovaWebView;
import org.apache.cordova.PluginResult;
import org.apache.cordova.PluginResult.Status;
import org.json.JSONArray;
import org.json.JSONException;

import android.content.Context;
import android.graphics.Rect;
import android.app.Activity;
import android.util.DisplayMetrics;
import android.view.View;
import android.view.ViewTreeObserver;
import android.view.ViewTreeObserver.OnGlobalLayoutListener;
import android.view.WindowInsets;
import android.view.inputmethod.InputMethodManager;

import android.os.Build;
import android.widget.FrameLayout;

public class CDVIonicKeyboard extends CordovaPlugin {
    private static final int KEYBOARD_VISIBLE_THRESHOLD_DP = 100;
    private OnGlobalLayoutListener list;
    private View rootView;
    private View mChildOfContent;
    private int usableHeightPrevious;
    private FrameLayout.LayoutParams frameLayoutParams;

    public void initialize(CordovaInterface cordova, CordovaWebView webView) {
        super.initialize(cordova, webView);
    }

    public boolean execute(String action, JSONArray args, final CallbackContext callbackContext) throws JSONException {
        if ("hide".equals(action)) {
            cordova.getThreadPool().execute(new Runnable() {
                public void run() {
                    Activity activity = cordova.getActivity();
                    if (activity == null) {
                        callbackContext.error("Activity is null");
                        return;
                    }
                    //http://stackoverflow.com/a/7696791/1091751
                    InputMethodManager inputManager = (InputMethodManager) activity.getSystemService(Context.INPUT_METHOD_SERVICE);
                    View v = activity.getCurrentFocus();

                    if (v == null) {
                        callbackContext.error("No current focus");
                    } else {
                        inputManager.hideSoftInputFromWindow(v.getWindowToken(), InputMethodManager.HIDE_NOT_ALWAYS);
                        callbackContext.success(); // Thread-safe.
                    }
                }
            });
            return true;
        }
        if ("show".equals(action)) {
            cordova.getThreadPool().execute(new Runnable() {
                public void run() {
                    Activity activity = cordova.getActivity();
                    if (activity == null) {
                        callbackContext.error("Activity is null");
                        return;
                    }
                    ((InputMethodManager) activity.getSystemService(Context.INPUT_METHOD_SERVICE)).toggleSoftInput(0, InputMethodManager.HIDE_IMPLICIT_ONLY);
                    callbackContext.success(); // Thread-safe.
                }
            });
            return true;
        }
        if ("init".equals(action)) {
            cordova.getThreadPool().execute(new Runnable() {
                public void run() {
                    Activity activity = cordova.getActivity();
                    if (activity == null) {
                        callbackContext.error("Activity is null");
                        return;
                    }
                	// Calculate density-independent pixels (dp) using activity resources display metrics.
                	// http://developer.android.com/guide/practices/screens_support.html
                	DisplayMetrics dm = activity.getResources().getDisplayMetrics();
                	final float density = dm.density;

                    //http://stackoverflow.com/a/4737265/1091751 detect if keyboard is showing
                    FrameLayout content = (FrameLayout) activity.findViewById(android.R.id.content);
                    if (content == null) {
                        callbackContext.error("Content view is null");
                        return;
                    }
                    rootView = content.getRootView();
                    list = new OnGlobalLayoutListener() {
                        int previousHeightDiff = 0;
                        @Override
                        public void onGlobalLayout() {
                            boolean resize = preferences.getBoolean("resizeOnFullScreen", false);
                            if (resize) {
                                possiblyResizeChildOfContent();
                            }
                            Rect r = new Rect();
                            //r will be populated with the coordinates of your view that area still visible.
                            rootView.getWindowVisibleDisplayFrame(r);

                            PluginResult result;

                            int rootViewHeight = rootView.getRootView().getHeight();
                            int heightDiff = Math.max(0, rootViewHeight - r.bottom);
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                WindowInsets insets = rootView.getRootWindowInsets();
                                if (insets != null) {
                                    int imeBottom = insets.getInsets(WindowInsets.Type.ime()).bottom;
                                    heightDiff = Math.max(heightDiff, imeBottom);
                                }
                            }

                            int pixelHeightDiff = (int)(heightDiff / density);
                            if (pixelHeightDiff > KEYBOARD_VISIBLE_THRESHOLD_DP && pixelHeightDiff != previousHeightDiff) { // if more than KEYBOARD_VISIBLE_THRESHOLD_DP dp, it's probably a keyboard...
                                String msg = "S" + Integer.toString(pixelHeightDiff);
                                result = new PluginResult(PluginResult.Status.OK, msg);
                                result.setKeepCallback(true);
                                callbackContext.sendPluginResult(result);
                            }
                            else if ( pixelHeightDiff != previousHeightDiff && ( previousHeightDiff - pixelHeightDiff ) > KEYBOARD_VISIBLE_THRESHOLD_DP ){
                            	String msg = "H";
                                result = new PluginResult(PluginResult.Status.OK, msg);
                                result.setKeepCallback(true);
                                callbackContext.sendPluginResult(result);
                            }
                            previousHeightDiff = pixelHeightDiff;
                        }

                        private void possiblyResizeChildOfContent() {
                            int usableHeightNow = computeUsableHeight();
                            if (usableHeightNow != usableHeightPrevious) {
                                int usableHeightSansKeyboard = mChildOfContent.getRootView().getHeight();
                                int heightDifference = usableHeightSansKeyboard - usableHeightNow;
                                if (heightDifference > (usableHeightSansKeyboard/4)) {
                                    frameLayoutParams.height = usableHeightSansKeyboard - heightDifference;
                                } else {
                                    frameLayoutParams.height = usableHeightSansKeyboard;
                                }
                                mChildOfContent.requestLayout();
                                usableHeightPrevious = usableHeightNow;
                            }
                        }

                        private int computeUsableHeight() {
                            Rect r = new Rect();
                            mChildOfContent.getWindowVisibleDisplayFrame(r);
                            return (r.bottom - r.top);
                        }
                    };

                    mChildOfContent = content.getChildAt(0);
                    rootView.getViewTreeObserver().addOnGlobalLayoutListener(list);
                    frameLayoutParams = (FrameLayout.LayoutParams) mChildOfContent.getLayoutParams();
                    PluginResult dataResult = new PluginResult(PluginResult.Status.OK);
                    dataResult.setKeepCallback(true);
                    callbackContext.sendPluginResult(dataResult);
                }
            });
            return true;
        }
        return false;  // Returning false results in a "MethodNotFound" error.
    }

    @Override
    public void onDestroy() {
        if (rootView != null && list != null) {
            ViewTreeObserver observer = rootView.getViewTreeObserver();
            if (observer != null && observer.isAlive()) {
                observer.removeOnGlobalLayoutListener(list);
            }
        }
        list = null;
        rootView = null;
        mChildOfContent = null;
        frameLayoutParams = null;
    }

}
