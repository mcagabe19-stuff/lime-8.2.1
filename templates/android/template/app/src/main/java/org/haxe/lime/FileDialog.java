package org.haxe.lime;

import android.content.Context;
import android.content.Intent;
import android.content.ContentResolver;
import android.os.ParcelFileDescriptor;
import android.net.Uri;
import android.util.Log;
import android.util.ArrayMap;
import android.widget.Toast;
import android.provider.DocumentsContract;
import android.webkit.MimeTypeMap;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.net.URI;

import org.haxe.extension.Extension;
import org.haxe.lime.HaxeObject;
import org.haxe.lime.GameActivity;

/*
	You can use the Android Extension class in order to hook
	into the Android activity lifecycle. This is not required
	for standard Java code, this is designed for when you need
	deeper integration.

	You can access additional references from the Extension class,
	depending on your needs:

	- Extension.assetManager (android.content.res.AssetManager)
	- Extension.callbackHandler (android.os.Handler)
	- Extension.mainActivity (android.app.Activity)
	- Extension.mainContext (android.content.Context)
	- Extension.mainView (android.view.View)

	You can also make references to static or instance methods
	and properties on Java classes. These classes can be included
	as single files using <java path="to/File.java" /> within your
	project, or use the full Android Library Project format (such
	as this example) in order to include your own AndroidManifest
	data, additional dependencies, etc.

	These are also optional, though this example shows a static
	function for performing a single task, like returning a value
	back to Haxe from Java.
*/
public class FileDialog extends Extension
{
	public static final String LOG_TAG = "FileDialog";
	private static final int OPEN_REQUEST_CODE = 990;

	public HaxeObject hxOBJ;
	// that's to prevent multiple FileDialogs from dispatching each others
	// kind it's kinda a shitty to handle it but idk anything better rn
	public boolean awaitingResults = false;

	public FileDialog(final HaxeObject haxeObject)
	{
		hxOBJ = haxeObject;
	}

	public static FileDialog createInstance(final HaxeObject haxeObject)
	{
		return GameActivity.creatFileDialog(haxeObject);
	}

	public void open(String filter, String defaultPath, String title)
	{
		Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
		intent.addCategory(Intent.CATEGORY_OPENABLE);

		if (defaultPath != null)
		{
			Log.d(LOG_TAG, "setting open dialog inital path...");
			File file = new File(defaultPath);
			if (file.exists())
			{
				Uri uri = Uri.fromFile(file);
				intent.putExtra(DocumentsContract.EXTRA_INITIAL_URI, uri);
				Log.d(LOG_TAG, "Set to " + uri.getPath() + "!");
			}
			else
			{
				Log.d(LOG_TAG, "Uh Oh the path doesn't exist :(");
			}
		}

		if (filter != null)
		{
			MimeTypeMap mimeType = MimeTypeMap.getSingleton();
			String extension = formatExtension(filter);
			String mime = mimeType.getMimeTypeFromExtension(extension);
			Log.d(LOG_TAG, "Setting mime to " + mime);
			intent.setType(mime);
		}
		else
		{
			intent.setType("*/*");
		}

		if (title != null)
		{
			Log.d(LOG_TAG, "Setting title to " + title);
			intent.putExtra(Intent.EXTRA_TITLE, title);
		}
		
		Log.d(LOG_TAG, "launching file picker intent!");
		awaitingResults = true;
		mainActivity.startActivityForResult(intent, OPEN_REQUEST_CODE);
	}


	@Override
	public boolean onActivityResult(int requestCode, int resultCode, Intent data)
	{
		if (hxOBJ != null && awaitingResults)
		{
			String uri = null;
			byte[] bytesData = null;

			if (data != null && data.getData() != null)
				uri = data.getData().toString();

			if (requestCode == OPEN_REQUEST_CODE && resultCode == mainActivity.RESULT_OK)
			{
				switch (requestCode)
				{
					case OPEN_REQUEST_CODE:
						try
						{
							Log.d(LOG_TAG, "getting file bytes from uri " + uri);
							bytesData = getFileBytes(data.getData());
						}
						catch (IOException e)
						{
							Log.e(LOG_TAG, "Failed to get file bytes\n" + e.getMessage());
						}
						break;
					default:
						break;
				}
			}

			hxOBJ.call4("jni_activity_results", requestCode, resultCode, uri, bytesData);
		}

		awaitingResults = false;
		return true;
	}

	public static String formatExtension(String extension) {
		if (extension.startsWith("*")) {
			extension = extension.substring(1);
		}
		if (extension.startsWith(".")) {
			extension = extension.substring(1);
		}
		return extension;
	}

	public static byte[] getFileBytes(Uri fileUri) throws IOException
	{
		ContentResolver contentResolver = mainContext.getContentResolver();
    	ParcelFileDescriptor parcelFileDescriptor = null;
    	FileInputStream fileInputStream = null;

    	try 
		{
    	    // Open a file descriptor for the file URI
    	    parcelFileDescriptor = contentResolver.openFileDescriptor(fileUri, "r");
    	    if (parcelFileDescriptor == null) 
			{
    	        throw new IOException("Failed to open file descriptor for URI: " + fileUri);
    	    }

    	    // Create a FileInputStream from the file descriptor
    	    fileInputStream = new FileInputStream(parcelFileDescriptor.getFileDescriptor());

    	    // Read the bytes into a byte array
    	    byte[] fileBytes = new byte[(int) parcelFileDescriptor.getStatSize()];
    	    fileInputStream.read(fileBytes);

    	    return fileBytes;

    	}
		catch (IOException ioe)
		{
			Log.e(LOG_TAG, "Failed to get file bytes\n" + ioe.getMessage());
			return new byte[0];
		}
		finally
		{
    	    // Close resources
    	    if (fileInputStream != null)
			{
    	        fileInputStream.close();
    	    }

    	    if (parcelFileDescriptor != null)
			{
    	        parcelFileDescriptor.close();
    	    }
    	}
	}
}
