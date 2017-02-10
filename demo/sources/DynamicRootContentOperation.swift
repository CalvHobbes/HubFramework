//
//  DynamicRootContentOperation.swift
//  HubFrameworkDemo
//
//  Created by Priya Marwaha on 1/24/17.
//  Copyright © 2017 Spotify. All rights reserved.
//

import Foundation
import HubFramework


class DynamicRootContentOperation: NSObject, HUBContentOperation {
    weak var delegate: HUBContentOperationDelegate?
    
  
     var  dynamicContentLoaded = false
    
    var rescheduled = false
    

    func perform(forViewURI viewURI: URL,
                 featureInfo: HUBFeatureInfo,
                 connectivityState: HUBConnectivityState,
                 viewModelBuilder: HUBViewModelBuilder,
                 previousError: Error?) {
        
       

        guard dynamicContentLoaded == false else {
     
      
            viewModelBuilder.setCustomDataValue(false, forKey: GitHubSearchCustomDataKeys.searchInProgress)

            
            delegate?.contentOperationDidFinish(self)
            return
        }
        
        getPageLayoutFromDCS()

        viewModelBuilder.setCustomDataValue(true, forKey: GitHubSearchCustomDataKeys.searchInProgress)
        
        delegate?.contentOperationDidFinish(self)

    }
    
    func getPageLayoutFromDCS() {
        // code below mimics an async call to DCSService to fetch page layout
        DispatchQueue.background.after(2, execute: { [weak self] in
            
            
            guard let `self` = self else {
                
                return
            }
            
            
            self.dynamicContentLoaded = true
            let operations = [RootContentOperation()]
            self.delegate?.contentOperationHasNewOperations(self, operations: operations)
        })

    }
}
