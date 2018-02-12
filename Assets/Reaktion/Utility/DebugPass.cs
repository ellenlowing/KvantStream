using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class DebugPass : MonoBehaviour {
	//Try using mouse position to send value
	// Use this for initialization
	void Start () {
		
	}
	
	// Update is called once per frame
	void Update () {
		if(Input.GetKeyDown("space")){
			print("1");
		}
	}
}
