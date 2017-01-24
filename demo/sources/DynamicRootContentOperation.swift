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

    func perform(forViewURI viewURI: URL,
                 featureInfo: HUBFeatureInfo,
                 connectivityState: HUBConnectivityState,
                 viewModelBuilder: HUBViewModelBuilder,
                 previousError: Error?) {
        
//        viewModelBuilder.navigationBarTitle = "Dynamic Hub Framework Demo App"
//        let rowBuilder = viewModelBuilder.builderForBodyComponentModel(withIdentifier: DefaultComponentNames.row)
//        rowBuilder.title = "Dynamic Operation Loader"
//        rowBuilder.subtitle = "A feature that enables you to add operations asynchronously"
        
        guard dynamicContentLoaded == false else {
            
               viewModelBuilder.setCustomDataValue(false, forKey: GitHubSearchCustomDataKeys.searchInProgress)
            delegate?.contentOperationDidFinish(self)
            return
        }
//        // Add an activity indicator overlay component
//        let activityIndicatorBuilder = viewModelBuilder.builderForOverlayComponentModel(withIdentifier: "activityIndicator")
//        activityIndicatorBuilder.componentName = DefaultComponentNames.activityIndicator
          viewModelBuilder.setCustomDataValue(true, forKey: GitHubSearchCustomDataKeys.searchInProgress)
        DispatchQueue.background.after(2, execute: { [weak self] in
        
            
            guard let `self` = self else {
                
                return
            }
            
            self.dynamicContentLoaded = true
            let operations = [RootContentOperation()]
            self.delegate?.contentOperationHasNewOperations(self, operations: operations)
        })
        delegate?.contentOperationDidFinish(self)

    }
}
