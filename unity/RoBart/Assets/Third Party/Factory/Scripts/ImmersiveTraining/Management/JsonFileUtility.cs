using System.IO;
using UnityEngine;

namespace ImmersiveTraining.Management
{
    public static class JsonFileUtility
    {
        public static string WriteToJson<T>(T dataObject)
        {
            try
            {
                return JsonUtility.ToJson(dataObject, true);
            }
            catch
            {
                Debug.LogError("Could not serialize to Json.");
                return null;
            }
        }

        public static T ReadFromJson<T>(string jsonString)
        {
            try
            {
                return JsonUtility.FromJson<T>(jsonString);
            }
            catch
            {
                Debug.LogError("Could not deserialize from Json.");
                return default(T);
            }
        }

        public static void WriteJsonToFile<T>(T dataObject, string path)
        {
            var filePath = CheckFilePath(path);
            if (filePath == null)
            {
                Debug.LogError("Directory does not exist. Aborting serialization and saving.");
                return;
            }
            string dataAsJson = WriteToJson<T>(dataObject);
            try
            {
                using StreamWriter outputFile = new(filePath);
                outputFile.WriteLine(dataAsJson);
            }
            catch (IOException e)
            {
                Debug.LogError("The file could not be saved: " + e.Message);
            }
        }

        public static T ReadJsonFromFile<T>(string path)
        {
            var filePath = CheckFilePath(path);
            if (filePath == null)
            {
                Debug.LogError("Directory does not exist. Aborting deserialization and writing.");
                return default(T);
            }

            string jsonString;
            try
            {
                using StreamReader reader = new(filePath);
                jsonString = reader.ReadToEnd();
                return ReadFromJson<T>(jsonString);
            }
            catch (IOException e)
            {
                Debug.LogError("The file could not be read: "+ e.Message);
                return default(T);
            }
        }

        static string CheckFilePath(string path)
        {
            if (!string.IsNullOrEmpty(path))
            {
                string fileNameAndPath;
#if UNITY_EDITOR
                fileNameAndPath = Path.Combine(Application.dataPath, path);
#else
            fileNameAndPath = Path.Combine(Application.persistentDataPath, path);
#endif
                var fileDirectory = Path.GetDirectoryName(fileNameAndPath);
                if (!string.IsNullOrEmpty(fileDirectory))
                {
                    if (Directory.Exists(fileDirectory))
                        return fileNameAndPath;
                }
            }
            return null;
        }
    }
}
